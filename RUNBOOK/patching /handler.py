"""
Patch outcome record writer -- minimal payload.

Runs in every member account. Reads an SSM Run Command terminal-status event and
writes one small, flat JSON object to the central patching bucket (cross-account).

Emits a record for EVERY terminal outcome, not only failures. Without a success
record, searching Splunk for an instance that patched cleanly returns nothing --
and "nothing" is indistinguishable from "never in scope" or "the pipeline broke".
Ops must be able to look up any instance and see patched / failed / not-attempted
with the command id.

    patch_outcome = "patched"        the document ran and succeeded
                    "failed"         it ran on the instance and failed
                    "not-attempted"  the instance was never touched

Sizing principle
----------------
Success needs no enrichment at all: it worked, there is nothing to explain. Zero
API calls, smallest record, highest volume.

For `failed` instances, AWS-RunPatchBaseline stdout already exists and carries the
error, the patch summary, everything -- and it is already indexed in Splunk. Those
records only need the join key and the classification.

For `not-attempted` instances (Terminated / Undeliverable) NO stdout object was
ever written, because the instance was never touched. That record is the only
evidence the instance was in scope and got skipped, so it must stand alone.

Record size is therefore inverse to stdout availability. Nothing stdout already
carries is duplicated here.

Rules
-----
  * The write MUST happen. Every enrichment call is independent and best-effort;
    a failure degrades the record, it never loses it.
  * The S3 put is deliberately NOT wrapped in try/except -- an exception is how
    the Lambda async failure destination gets exercised.
  * Fields are flat. Splunk needs no FIELDALIAS stanzas.
"""

import json
import logging
import os
import time
from datetime import datetime, timezone

import boto3
from botocore.config import Config

LOG = logging.getLogger()
LOG.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

_CFG = Config(retries={"max_attempts": 3, "mode": "adaptive"})
S3 = boto3.client("s3", config=Config(retries={"max_attempts": 5, "mode": "adaptive"}))
SSM = boto3.client("ssm", config=_CFG)
EC2 = boto3.client("ec2", config=_CFG)

BUCKET = os.environ["BUCKET_NAME"]
PREFIX = os.environ["S3_PREFIX"].strip("/")
KMS_KEY_ARN = os.environ.get("KMS_KEY_ARN") or None
# Only when the bucket has ACLs ENABLED. With BucketOwnerEnforced, leave unset.
OBJECT_ACL = os.environ.get("OBJECT_ACL") or None
ENRICH = os.environ.get("ENRICH", "true").lower() == "true"

# Turn OFF if Splunk already has an instance-id -> owner lookup. Doing the
# enrichment at search time saves ~160 bytes per record, one API call per
# invocation, and avoids stale tags frozen into an immutable object.
INCLUDE_TAGS = os.environ.get("INCLUDE_INSTANCE_TAGS", "true").lower() == "true"

SCHEMA_VERSION = 1

# StatusDetails -> the only distinction that changes what a team does next.
#
# "Terminated" means the parent command breached its error threshold and the
# system cancelled this invocation: the instance was NEVER TOUCHED. Under the
# zero-tolerance rate-control policy this is routine, high-volume, and a
# FAILURE -- the instance is unpatched. It needs a re-run, not an investigation.
NOT_ATTEMPTED = {
    "Terminated", "Undeliverable", "Delivery Timed Out",
    "Invalid Platform", "Access Denied", "Cancelled",
}
FAILED = {"Failed", "Execution Timed Out"}
SUCCEEDED = {"Success"}

# ListCommands results keyed by command-id. The ~37 invocations of one halted
# command share warm containers and all ask about the same command.
_CMD_CACHE = {}


# ---------------------------------------------------------------- helpers

def _safe(value, default="unknown", limit=128):
    """S3-key-safe token. Never let an event field inject a path separator."""
    if not value:
        return default
    cleaned = "".join(c if (c.isalnum() or c in "-_.") else "-" for c in str(value))
    return cleaned[:limit] or default


def _classify(status_details, event_status):
    """-> patched | failed | not-attempted | unknown

    Success is decided from the event alone; no enrichment is needed or made.
    """
    if event_status in SUCCEEDED:
        return "patched"
    if status_details in NOT_ATTEMPTED:
        return "not-attempted"
    if status_details in FAILED:
        return "failed"
    # Fall back to the coarse event status when enrichment was unavailable.
    if status_details is None and event_status in ("Undeliverable", "Cancelled"):
        return "not-attempted"
    if status_details is None and event_status in ("Failed", "TimedOut"):
        return "failed"
    return "unknown"


def _build_key(event):
    detail = event.get("detail") or {}
    ts = event.get("time") or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    day = ts[:10]                                   # dt= partition
    compact = ts.replace("-", "").replace(":", "")
    return (
        f"{PREFIX}/dt={day}/{_safe(event.get('account'))}/"
        f"{_safe(detail.get('status'))}_"
        f"{_safe(detail.get('instance-id'), 'no-instance')}_"
        f"{_safe(detail.get('command-id'), 'no-command')}_"
        f"{compact}_{_safe(event.get('id'))}.json"
    )


# ------------------------------------------------------------ enrichment
# None of these raise.

def _status_details(command_id, instance_id):
    """The one field the EventBridge event does not carry, and the only source
    of `Terminated`.

    The Run Command API is eventually consistent, so a terminal-status event can
    briefly outrun the queryable invocation record. One short retry covers it.
    """
    for attempt in range(3):
        try:
            r = SSM.get_command_invocation(CommandId=command_id, InstanceId=instance_id)
            return r.get("StatusDetails")
        except Exception as exc:                                  # noqa: BLE001
            LOG.warning("get_command_invocation attempt %s: %s", attempt + 1, exc)
            time.sleep(2 ** attempt)
    return None


def _command_fields(command_id):
    """Six fields that make a not-attempted record self-documenting: a reader
    needs no knowledge of the rate-control policy to understand it."""
    if command_id in _CMD_CACHE:
        return _CMD_CACHE[command_id]
    out = {}
    try:
        cmds = SSM.list_commands(CommandId=command_id).get("Commands") or []
        if cmds:
            c = cmds[0]
            out = {
                "target_count": c.get("TargetCount"),
                "error_count": c.get("ErrorCount"),
                "completed_count": c.get("CompletedCount"),
                "max_errors": c.get("MaxErrors"),
                "max_concurrency": c.get("MaxConcurrency"),
                "command_comment": c.get("Comment") or None,
            }
    except Exception as exc:                                      # noqa: BLE001
        LOG.warning("list_commands failed: %s", exc)
    if len(_CMD_CACHE) > 100:
        _CMD_CACHE.clear()
    _CMD_CACHE[command_id] = out
    return out


def _ping_status(instance_id):
    """Usually IS the answer for a not-attempted instance."""
    try:
        info = SSM.describe_instance_information(
            Filters=[{"Key": "InstanceIds", "Values": [instance_id]}]
        ).get("InstanceInformationList") or []
        return info[0].get("PingStatus") if info else None
    except Exception as exc:                                      # noqa: BLE001
        LOG.warning("describe_instance_information failed: %s", exc)
        return None


def _tags(instance_id):
    """Only when Splunk has no instance-id -> owner lookup of its own."""
    wanted = {"Name": "instance_name", "Application": "tag_application",
              "Owner": "tag_owner", "patch:wave": "tag_patch_wave"}
    try:
        r = EC2.describe_instances(InstanceIds=[instance_id])
        for res in r.get("Reservations", []):
            for inst in res.get("Instances", []):
                return {wanted[t["Key"]]: t["Value"]
                        for t in inst.get("Tags", []) if t["Key"] in wanted}
        return {}
    except Exception as exc:                                      # noqa: BLE001
        LOG.warning("describe_instances failed: %s", exc)
        return {}


# ---------------------------------------------------------------- handler

def handler(event, context):
    key = _build_key(event)
    detail = event.get("detail") or {}
    command_id = detail.get("command-id")
    instance_id = detail.get("instance-id")
    event_status = detail.get("status")

    is_success = event_status in SUCCEEDED

    # Success costs ZERO API calls -- the event alone is conclusive, and this is
    # the highest-volume class by a wide margin.
    status_details = "Success" if is_success else None
    if ENRICH and not is_success and command_id and instance_id:
        status_details = _status_details(command_id, instance_id)

    patch_outcome = _classify(status_details, event_status)

    rec = {
        "schema_version": SCHEMA_VERSION,
        "record_type": "invocation" if instance_id else "command",
        "account": event.get("account"),
        "region": event.get("region"),
        "instance_id": instance_id,
        "command_id": command_id,
        "document": detail.get("document-name"),
        "event_time": event.get("time"),
        "patch_outcome": patch_outcome,
        "status": event_status,
        "status_details": status_details,
    }
    if not instance_id:
        rec.pop("instance_id")

    # Extra context ONLY where stdout does not exist to supply it.
    #   patched -> nothing to explain
    #   failed  -> a full stdout object is already in Splunk; join on command_id
    #   not-attempted -> NO stdout was ever written; this record must stand alone
    needs_context = patch_outcome not in ("patched", "failed")

    if ENRICH and needs_context and command_id:
        rec.update(_command_fields(command_id))

    if ENRICH and needs_context and instance_id:
        rec["agent_ping_status"] = _ping_status(instance_id)

    if ENRICH and INCLUDE_TAGS and instance_id:
        rec.update(_tags(instance_id))

    body = (json.dumps(rec, separators=(",", ":"), default=str) + "\n").encode("utf-8")

    args = {
        "Bucket": BUCKET,
        "Key": key,
        "Body": body,
        "ContentType": "application/json",
    }
    if KMS_KEY_ARN:
        args["ServerSideEncryption"] = "aws:kms"
        args["SSEKMSKeyId"] = KMS_KEY_ARN
    if OBJECT_ACL:
        args["ACL"] = OBJECT_ACL

    # Deliberately NOT wrapped. An exception here is how the Lambda async failure
    # destination gets exercised -- swallowing it would make a broken bucket
    # policy or a revoked KMS grant invisible.
    S3.put_object(**args)

    LOG.info("patch outcome record %s (%s bytes): %s",
             key, len(body), json.dumps(rec, default=str))
    return {"bucket": BUCKET, "key": key, "bytes": len(body)}
