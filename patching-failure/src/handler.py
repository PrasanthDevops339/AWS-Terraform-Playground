"""Schema-v2 SSM patch outcomes; enrichment is optional, S3 delivery is not.

The Lambda runs on the main Python thread in the managed Linux runtime. A
POSIX timer bounds all enrichment (including SDK work) to ten seconds, leaving
at least twenty seconds of the configured timeout for writing the record.
"""

import json
import logging
import os
import signal
import time
from collections import OrderedDict
from contextlib import contextmanager
from datetime import datetime, timezone

import boto3
from botocore.config import Config

LOG = logging.getLogger(__name__)
LOG.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

# SDK retries must not multiply the handler's short eventual-consistency retry.
_CFG = Config(connect_timeout=1, read_timeout=2,
              retries={"total_max_attempts": 1, "mode": "standard"})
S3 = boto3.client("s3", config=Config(
    connect_timeout=2, read_timeout=3,
    retries={"total_max_attempts": 3, "mode": "standard"},
))
SSM = boto3.client("ssm", config=_CFG)
EC2 = boto3.client("ec2", config=_CFG)

BUCKET = os.environ["BUCKET_NAME"]
PREFIX = os.environ["S3_PREFIX"].strip("/")
KMS_KEY_ARN = os.environ.get("KMS_KEY_ARN") or None
OBJECT_ACL = os.environ.get("OBJECT_ACL") or None
ENRICH = os.environ.get("ENRICH", "true").lower() == "true"
INCLUDE_TAGS = os.environ.get("INCLUDE_INSTANCE_TAGS", "true").lower() == "true"
SCHEMA_VERSION = 2
ENRICHMENT_SECONDS = 10.0
WRITE_RESERVE_SECONDS = 20.0
CALL_SECONDS = 3.0
CACHE_TTL_SECONDS = 15.0
_CMD_CACHE = OrderedDict()

CANONICAL = {
    "success": "Success", "failed": "Failed", "cancelled": "Cancelled",
    "timedout": "TimedOut", "terminated": "Terminated",
    "undeliverable": "Undeliverable", "deliverytimedout": "Delivery Timed Out",
    "executiontimedout": "Execution Timed Out", "invalidplatform": "Invalid Platform",
    "accessdenied": "Access Denied", "incomplete": "Incomplete",
    "rateexceeded": "Rate Exceeded", "noinstancesintag": "No Instances In Tag",
}
NOT_ATTEMPTED = {"terminated", "undeliverable", "deliverytimedout",
                 "invalidplatform", "accessdenied"}
CONTEXT_FIELDS = {
    "TargetCount": "target_count", "ErrorCount": "error_count",
    "CompletedCount": "completed_count", "MaxErrors": "max_errors",
    "MaxConcurrency": "max_concurrency", "Comment": "command_comment",
}


class _EnrichmentDeadline(BaseException):
    """Bypass best-effort Exception handlers and stop the whole enrichment phase."""


def _expired(signum, frame):
    raise _EnrichmentDeadline()


@contextmanager
def _budget(context):
    remaining = context.get_remaining_time_in_millis() / 1000 if context else 30.0
    seconds = max(0.0, min(ENRICHMENT_SECONDS, remaining - WRITE_RESERVE_SECONDS))
    deadline = time.monotonic() + seconds
    if seconds == 0:
        yield deadline
        return
    previous_handler = signal.getsignal(signal.SIGALRM)
    previous_timer = signal.getitimer(signal.ITIMER_REAL)
    started = time.monotonic()
    signal.signal(signal.SIGALRM, _expired)
    try:
        signal.setitimer(signal.ITIMER_REAL, seconds)
        yield deadline
    except _EnrichmentDeadline:
        LOG.warning("Enrichment budget exhausted; writing available fields")
    except Exception:
        LOG.exception("Enrichment unavailable; writing available fields")
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous_handler)
        if previous_timer[0]:
            signal.setitimer(signal.ITIMER_REAL,
                             max(0.001, previous_timer[0] - (time.monotonic() - started)),
                             previous_timer[1])


def _normalize(value):
    return "".join(c for c in str(value or "").lower() if c.isalnum())


def _operation(parameters):
    value = (parameters or {}).get("Operation", [])
    value = value[0] if isinstance(value, list) and value else value
    return {"scan": "Scan", "install": "Install"}.get(str(value).lower(), "unknown")


def _classify(status_details, event_status, operation):
    event = _normalize(event_status)
    details = _normalize(status_details)
    if event == "success":
        return {"Scan": "scanned", "Install": "patched"}.get(operation, "unknown")
    if event in NOT_ATTEMPTED or details in NOT_ATTEMPTED:
        return "not-attempted"
    # Only an aggregate invocation result establishes a coarse Failed outcome.
    # Cancelled/TimedOut events alone cannot establish whether execution started.
    if details in {"failed", "executiontimedout"} or event == "executiontimedout":
        return "failed"
    return "unknown"


def _safe(value):
    return "".join(c if c.isascii() and (c.isalnum() or c in "-_.") else "-"
                   for c in str(value))[:128]


def _read(method, kwargs, accept, deadline):
    """Retry missing/eventually-consistent results; all calls share one deadline."""
    for attempt in range(3):
        if deadline - time.monotonic() < CALL_SECONDS:
            return None
        try:
            result = accept(method(**kwargs))
            if result is not None:
                return result
        except Exception as exc:
            LOG.warning("%s unavailable: %s", getattr(method, "__name__", "enrichment API"), exc)
            code = getattr(exc, "response", {}).get("Error", {}).get("Code", "")
            if code in {"AccessDenied", "AccessDeniedException", "InvalidCommandId", "InvalidInstanceId"}:
                return None
        if attempt < 2:
            delay = 0.25 * (2 ** attempt)
            if deadline - time.monotonic() < CALL_SECONDS + delay:
                return None
            time.sleep(delay)
    return None


def _status_details(command_id, instance_id, deadline):
    def accept(response):
        for invocation in response.get("CommandInvocations", []):
            if invocation.get("CommandId") != command_id or invocation.get("InstanceId") != instance_id:
                continue
            status = _normalize(invocation.get("StatusDetails"))
            if status in CANONICAL:
                return CANONICAL[status]
        return None

    return _read(SSM.list_command_invocations,
                 {"CommandId": command_id, "InstanceId": instance_id, "Details": False},
                 accept, deadline)


def _command(command_id, deadline):
    cached = _CMD_CACHE.get(command_id)
    if cached and time.monotonic() < cached[0]:
        _CMD_CACHE.move_to_end(command_id)
        return cached[1]
    _CMD_CACHE.pop(command_id, None)

    def accept(response):
        return next((c for c in response.get("Commands", [])
                     if c.get("CommandId") == command_id and _operation(c.get("Parameters")) != "unknown"), None)

    command = _read(SSM.list_commands, {"CommandId": command_id}, accept, deadline)
    if command is not None:
        _CMD_CACHE[command_id] = (time.monotonic() + CACHE_TTL_SECONDS, command)
        if len(_CMD_CACHE) > 128:
            _CMD_CACHE.popitem(last=False)
    return command or {}


def _enrich(rec, deadline):
    # Classification takes precedence over supplementary metadata on failures.
    if rec["record_type"] == "invocation" and _normalize(rec["status"]) not in NOT_ATTEMPTED | {"success", "executiontimedout"}:
        rec["status_details"] = _status_details(rec["command_id"], rec["instance_id"], deadline)
    outcome = _classify(rec["status_details"], rec["status"], rec["operation"])
    needs_context = outcome in {"unknown", "not-attempted"}
    if rec["operation"] == "unknown" or needs_context or rec["record_type"] == "command":
        command = _command(rec["command_id"], deadline)
        if rec["operation"] == "unknown":
            rec["operation"] = _operation(command.get("Parameters"))
        outcome = _classify(rec["status_details"], rec["status"], rec["operation"])
        needs_context = outcome in {"unknown", "not-attempted"}
        if needs_context or rec["record_type"] == "command":
            rec.update({target: command[source] for source, target in CONTEXT_FIELDS.items() if source in command})
    if needs_context and rec["record_type"] == "invocation":
        info = _read(SSM.describe_instance_information,
                     {"Filters": [{"Key": "InstanceIds", "Values": [rec["instance_id"]]}]},
                     lambda r: r.get("InstanceInformationList", []), deadline)
        rec["agent_ping_status"] = info[0].get("PingStatus") if info else None
        if INCLUDE_TAGS and rec["instance_id"].startswith("i-"):
            reservations = _read(EC2.describe_instances, {"InstanceIds": [rec["instance_id"]]},
                                 lambda r: r.get("Reservations", []), deadline)
            wanted = {"Name": "instance_name", "Application": "tag_application",
                      "Owner": "tag_owner", "patch:wave": "tag_patch_wave"}
            for reservation in reservations or []:
                for instance in reservation.get("Instances", []):
                    if instance.get("InstanceId") == rec["instance_id"]:
                        rec.update({wanted[t["Key"]]: t["Value"] for t in instance.get("Tags", []) if t["Key"] in wanted})


def handler(event, context):
    source = event.get("source")
    detail_type = event.get("detail-type")
    is_canary = source == "custom.patch-canary" and detail_type == "canary"
    types = {"EC2 Command Invocation Status-change Notification": "invocation",
             "EC2 Command Status-change Notification": "command"}
    if not is_canary and (source != "aws.ssm" or detail_type not in types):
        raise ValueError("Expected an SSM status event or a patch canary; unwrap failure destinations before replay")
    for field in ("id", "time", "account", "region"):
        if not isinstance(event.get(field), str) or not event[field]:
            raise ValueError(f"Event is missing {field}")
    timestamp = datetime.fromisoformat(event["time"].replace("Z", "+00:00"))
    if timestamp.tzinfo is None:
        raise ValueError("Event time must include a timezone")
    timestamp = timestamp.astimezone(timezone.utc)
    detail = event.get("detail") or {}
    record_type = "canary" if is_canary else types[detail_type]
    if not is_canary and (not detail.get("command-id") or not detail.get("status") or not detail.get("document-name")):
        raise ValueError("SSM event is missing command-id, document-name or status")
    if record_type == "invocation" and not detail.get("instance-id"):
        raise ValueError("Invocation event is missing instance-id")
    status = None if is_canary else detail["status"]
    normalized = _normalize(status)
    rec = {
        "schema_version": SCHEMA_VERSION,
        "record_type": record_type,
        "event_id": event["id"],
        "account": event["account"],
        "region": event["region"],
        "command_id": None if is_canary else detail["command-id"],
        "document": None if is_canary else detail["document-name"],
        "event_time": timestamp.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "operation": "unknown" if is_canary else _operation(detail.get("parameters")),
        "status": status,
        "status_details": CANONICAL.get(normalized) if normalized in NOT_ATTEMPTED | {"success", "executiontimedout"} else None,
    }
    if record_type == "invocation":
        rec["instance_id"] = detail["instance-id"]
    if ENRICH and not is_canary:
        with _budget(context) as deadline:
            _enrich(rec, deadline)
    # A command summary or a canary never makes an instance-level patch claim.
    rec["patch_outcome"] = (_classify(rec["status_details"], rec["status"], rec["operation"])
                            if record_type == "invocation" else "unknown")
    key = (f"{PREFIX}/dt={timestamp:%Y-%m-%d}/{_safe(event['account'])}/"
           f"{_safe(event['region'])}/{record_type}_{_safe(event['id'])}.json")
    body = (json.dumps(rec, separators=(",", ":"), default=str) + "\n").encode("utf-8")
    args = {"Bucket": BUCKET, "Key": key, "Body": body, "ContentType": "application/json"}
    if KMS_KEY_ARN:
        args.update(ServerSideEncryption="aws:kms", SSEKMSKeyId=KMS_KEY_ARN)
    if OBJECT_ACL:
        args["ACL"] = OBJECT_ACL
    # Do not swallow this exception: Lambda must retry and send its failure record.
    S3.put_object(**args)
    LOG.info("patch outcome %s (%s bytes): %s", key, len(body), json.dumps(rec))
    return {"bucket": BUCKET, "key": key, "bytes": len(body)}
