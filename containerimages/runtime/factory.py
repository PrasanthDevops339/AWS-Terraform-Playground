"""Trusted release control plane. Candidate content is never executed here."""
import collections
import datetime as dt
import hashlib
import io
import json
import os
import re
import time
from functools import lru_cache

import boto3
from boto3.dynamodb.conditions import Attr, Key
from botocore.config import Config

DIGEST = re.compile(r"sha256:[0-9a-f]{64}\Z")
SERIES = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")
SEVERITIES = {"CRITICAL", "HIGH", "MEDIUM", "LOW", "INFORMATIONAL", "UNTRIAGED"}


class GateClosed(Exception):
    """Definitive rejection. Never retry as successful."""


class Pending(Exception):
    """Required authoritative evidence has not arrived yet."""


def settings():
    return {k: os.environ[k] for k in (
        "ACCOUNT_ID", "PRIMARY_REGION", "SECONDARY_REGION", "STAGING_REPOSITORY",
        "APPROVED_REPOSITORY", "TABLE_NAME", "EVIDENCE_BUCKET", "PIPELINE_ARN",
        "RELEASE_SERIES", "SOURCE_REVISION", "ALERT_TOPIC_ARN")}


def client(service, region=None):
    return cached_client(service, region or os.environ["PRIMARY_REGION"])


@lru_cache
def cached_client(service, region):
    return boto3.client(service, region_name=region,
                        config=Config(retries={"mode": "standard", "total_max_attempts": 4},
                                      connect_timeout=5, read_timeout=20))


client.cache_clear = cached_client.cache_clear


@lru_cache
def table():
    return boto3.resource("dynamodb", region_name=os.environ["PRIMARY_REGION"],
                          config=Config(retries={"mode": "standard", "total_max_attempts": 4},
                                        connect_timeout=5, read_timeout=20)).Table(os.environ["TABLE_NAME"])


def timestamp():
    return int(time.time())


def iso_epoch(value):
    if isinstance(value, dt.datetime):
        return int(value.timestamp())
    return int(dt.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp())


def digest_checked(value):
    if not isinstance(value, str) or not DIGEST.fullmatch(value):
        raise GateClosed("Invalid image digest")
    return value


def repository_name(value, region, cfg):
    prefix = f"arn:aws:ecr:{region}:{cfg['ACCOUNT_ID']}:repository/"
    if value.startswith("arn:"):
        if not value.startswith(prefix):
            raise GateClosed("Repository ARN outside configured account/region")
        return value[len(prefix):]
    return value


def get_record(pk):
    return table().get_item(Key={"pk": pk}, ConsistentRead=True).get("Item")


def update(pk, fields, condition=None):
    names = {f"#f{i}": k for i, k in enumerate(fields)}
    values = {f":v{i}": v for i, v in enumerate(fields.values())}
    args = dict(Key={"pk": pk}, UpdateExpression="SET " + ", ".join(
        f"#f{i} = :v{i}" for i in range(len(fields))),
        ExpressionAttributeNames=names, ExpressionAttributeValues=values)
    if condition is not None:
        args["ConditionExpression"] = condition
    table().update_item(**args)


def metric(name, value=1):
    # CloudWatch EMF keeps high-cardinality digests out of metric dimensions.
    print(json.dumps({"_aws": {"Timestamp": timestamp() * 1000,
          "CloudWatchMetrics": [{"Namespace": "ContainerImages",
          "Dimensions": [["Factory"]], "Metrics": [{"Name": name, "Unit": "Count"}]}]},
          "Factory": os.environ["FACTORY_NAME"], name: value}))


def evidence(digest, phase, payload):
    key = f"releases/{digest}/{timestamp()}-{phase}-{hashlib.sha256(json.dumps(payload, default=str, sort_keys=True).encode()).hexdigest()[:16]}.json"
    body = json.dumps(payload, default=str, sort_keys=True).encode()
    client("s3").upload_fileobj(io.BytesIO(body), os.environ["EVIDENCE_BUCKET"], key,
                                ExtraArgs={"ContentType": "application/json"})
    return key


def notify(subject, payload):
    client("sns").publish(TopicArn=os.environ["ALERT_TOPIC_ARN"], Subject=subject,
                          Message=json.dumps(payload, default=str))


def image_digest(ecr, repository, image_id):
    result = ecr.describe_images(repositoryName=repository, imageIds=[image_id])["imageDetails"]
    if len(result) != 1:
        raise GateClosed("Expected one image")
    return digest_checked(result[0]["imageDigest"])


def verified_build(build_arn, cfg):
    image = client("imagebuilder").get_image(imageBuildVersionArn=build_arn)["image"]
    if image.get("sourcePipelineArn") != cfg["PIPELINE_ARN"]:
        raise GateClosed("Build belongs to another pipeline")
    if image.get("state", {}).get("status") != "AVAILABLE":
        raise GateClosed("Build is not AVAILABLE")
    if image.get("imageTestsConfiguration", {}).get("imageTestsEnabled") is not True:
        raise GateClosed("Image Builder tests were disabled")
    recipe = image.get("containerRecipe", {})
    if recipe.get("targetRepository", {}).get("repositoryName") != cfg["STAGING_REPOSITORY"]:
        raise GateClosed("Unexpected recipe repository")
    prefix = f"{cfg['ACCOUNT_ID']}.dkr.ecr.{cfg['PRIMARY_REGION']}.amazonaws.com/{cfg['STAGING_REPOSITORY']}"
    digests = set()
    for output in image.get("outputResources", {}).get("containers", []):
        if output.get("region") != cfg["PRIMARY_REGION"]:
            raise GateClosed("Unexpected build output region")
        for uri in output.get("imageUris", []):
            if uri.startswith(prefix + "@"):
                image_id = {"imageDigest": digest_checked(uri[len(prefix) + 1:])}
            elif uri.startswith(prefix + ":"):
                image_id = {"imageTag": uri[len(prefix) + 1:]}
            else:
                raise GateClosed("Unexpected build output URI")
            digests.add(image_digest(client("ecr"), cfg["STAGING_REPOSITORY"], image_id))
    if len(digests) != 1:
        raise GateClosed("Expected one x86_64 output digest")
    return digests.pop()


def scan_record_key(region, repository, digest):
    return f"SCAN#{region}#{repository}#{digest}"


def scan_counts(repository, digest, cfg, region=None):
    """Require completion AND current coverage; aggregate every unresolved finding."""
    region = region or cfg["PRIMARY_REGION"]
    ecr = client("ecr", region)
    try:
        response = ecr.describe_image_scan_findings(repositoryName=repository,
                                                   imageId={"imageDigest": digest}, maxResults=100)
    except (ecr.exceptions.ScanNotFoundException, ecr.exceptions.ImageNotFoundException) as exc:
        raise Pending("Scan not available") from exc
    status = response.get("imageScanStatus", {}).get("status")
    if status in {"PENDING", "IN_PROGRESS"}:
        raise Pending("Scan still running")
    if status != "ACTIVE":
        raise GateClosed(f"Enhanced scan coverage is not ACTIVE: {status}")
    scan = response.get("imageScanFindings", {})
    completion = get_record(scan_record_key(region, repository, digest))
    # API completion timestamp is independent proof when EventBridge delivery was lost.
    if not completion and not scan.get("imageScanCompletedAt"):
        raise Pending("No initial scan completion evidence")
    if response.get("imageId", {}).get("imageDigest") != digest:
        raise GateClosed("Scan digest mismatch")
    if response.get("repositoryName") != repository or response.get("registryId") != cfg["ACCOUNT_ID"]:
        raise GateClosed("Scan repository/account mismatch")
    # The summary can legitimately omit CRITICAL when zero; absence of the whole
    # summary cannot serve as evidence. ListFindings also includes SUPPRESSED.
    summary = scan.get("findingSeverityCounts")
    if not isinstance(summary, dict):
        raise Pending("Scan summary missing")
    for key, count in summary.items():
        if not isinstance(count, int) or isinstance(count, bool) or count < 0:
            raise GateClosed("Malformed severity count")
    counts = collections.Counter()
    filters = {
        "awsAccountId": [{"comparison": "EQUALS", "value": cfg["ACCOUNT_ID"]}],
        "ecrImageRepositoryName": [{"comparison": "EQUALS", "value": repository}],
        "ecrImageHash": [{"comparison": "EQUALS", "value": digest}],
        "findingStatus": [{"comparison": "EQUALS", "value": state} for state in ("ACTIVE", "SUPPRESSED")],
    }
    for page in client("inspector2", region).get_paginator("list_findings").paginate(filterCriteria=filters):
        for finding in page["findings"]:
            severity = finding.get("severity")
            if severity not in SEVERITIES:
                raise GateClosed("Unknown finding severity")
            counts[severity] += 1
    # Event/API and Inspector APIs are eventually consistent: either can block.
    counts["CRITICAL"] = max(counts["CRITICAL"], summary.get("CRITICAL", 0),
                             int((completion or {}).get("critical", 0)))
    if counts["CRITICAL"]:
        raise GateClosed(f"{counts['CRITICAL']} unresolved Critical finding(s)")
    return dict(counts)


def allocate_version(digest, cfg):
    pk = f"RELEASE#{digest}"
    record = get_record(pk)
    if record.get("version"):
        return record["version"]
    if not SERIES.fullmatch(cfg["RELEASE_SERIES"]):
        raise GateClosed("Invalid release series")
    counter = table().update_item(
        Key={"pk": f"COUNTER#{cfg['RELEASE_SERIES']}"},
        UpdateExpression="ADD next_patch :one", ExpressionAttributeValues={":one": 1},
        ReturnValues="UPDATED_NEW")["Attributes"]["next_patch"]
    version = f"{cfg['RELEASE_SERIES']}.{int(counter) - 1}"
    try:
        update(pk, {"version": version}, Attr("version").not_exists() & Attr("pk").exists())
        return version
    except table().meta.client.exceptions.ConditionalCheckFailedException:
        # Another execution won; allocated gaps are intentionally never reused.
        return get_record(pk)["version"]


def ingest(event, context):
    cfg = settings()
    if event.get("account") != cfg["ACCOUNT_ID"] or event.get("region") not in {
            cfg["PRIMARY_REGION"], cfg["SECONDARY_REGION"]}:
        raise GateClosed("Event account/region mismatch")
    detail = event.get("detail", {})
    if event.get("source") == "aws.inspector2" and event.get("detail-type") == "Inspector2 Scan":
        if detail.get("scan-status") != "INITIAL_SCAN_COMPLETE":
            return {"ignored": True}
        repo = repository_name(detail.get("repository-name", ""), event["region"], cfg)
        if repo not in {cfg["STAGING_REPOSITORY"], cfg["APPROVED_REPOSITORY"]}:
            return {"ignored": True}
        digest = digest_checked(detail.get("image-digest"))
        counts = detail.get("finding-severity-counts")
        if not isinstance(counts, dict) or any(type(v) is not int or v < 0 for v in counts.values()):
            raise GateClosed("Invalid scan completion counts")
        when = iso_epoch(event["time"])
        pk = scan_record_key(event["region"], repo, digest)
        try:
            update(pk, {"completed_at": when, "critical": counts.get("CRITICAL", 0),
                        "event_id": event["id"]},
                   Attr("completed_at").not_exists() | Attr("completed_at").lt(when))
        except table().meta.client.exceptions.ConditionalCheckFailedException:
            pass  # Duplicate or older completion must not replace newer evidence.
        return {"recorded": digest}
    if event.get("source") != "aws.imagebuilder" or event["region"] != cfg["PRIMARY_REGION"]:
        return {"ignored": True}
    if detail.get("state", {}).get("status") != "AVAILABLE":
        return {"ignored": True}
    resources = event.get("resources", [])
    if len(resources) != 1:
        raise GateClosed("Expected one Image Builder resource")
    build_arn = resources[0]
    digest = verified_build(build_arn, cfg)
    record = {"pk": f"RELEASE#{digest}", "kind": "RELEASE", "digest": digest,
              "build_arn": build_arn, "created_at": timestamp(), "status": "CANDIDATE",
              "source_revision": cfg["SOURCE_REVISION"], "eligible": False}
    try:
        table().put_item(Item=record, ConditionExpression=Attr("pk").not_exists())
    except table().meta.client.exceptions.ConditionalCheckFailedException:
        record = get_record(record["pk"])
    update("CONTROL#heartbeat", {"last_build": timestamp()})
    if record["status"] == "RELEASED":
        return {"already_released": digest}
    # The build ARN is the event idempotency key; replay cannot start a bypass path.
    name = hashlib.sha256(build_arn.encode()).hexdigest()
    try:
        client("stepfunctions").start_execution(stateMachineArn=os.environ["STATE_MACHINE_ARN"],
            name=name, input=json.dumps({"digest": digest, "started_at": timestamp()}))
    except client("stepfunctions").exceptions.ExecutionAlreadyExists:
        pass
    return {"digest": digest}


def evaluate(digest, cfg):
    record = get_record(f"RELEASE#{digest}")
    if not record or record.get("status") == "WITHDRAWN":
        raise GateClosed("Candidate missing or withdrawn")
    if verified_build(record["build_arn"], cfg) != digest:
        raise GateClosed("Build digest changed")
    counts = scan_counts(cfg["STAGING_REPOSITORY"], digest, cfg)
    key = evidence(digest, "gate", {"digest": digest, "counts": counts,
                   "build_arn": record["build_arn"], "policy": "zero-unresolved-critical-v1"})
    version = allocate_version(digest, cfg)
    # A trusted workflow retry can recover a failed run only by verifying the
    # original build and passing the current scan again. Preserve its version.
    fields = {"scan_evidence": key, "accepted_at": timestamp()}
    if record.get("status") == "BLOCKED":
        fields["status"] = "CANDIDATE"
    update(record["pk"], fields, ~Attr("status").eq("WITHDRAWN"))
    return {"status": "ACCEPTED", "digest": digest, "version": version}


def control(event, context):
    cfg = settings()
    digest = digest_checked(event["digest"])
    action = event["action"]
    try:
        if action == "evaluate":
            if timestamp() - int(event["started_at"]) >= int(os.environ["SCAN_TIMEOUT_SECONDS"]):
                metric("ScanTimeout")
                raise GateClosed("Scan acceptance deadline exceeded")
            return evaluate(digest, cfg)
        if action == "replication":
            if timestamp() - iso_epoch(event["started_at"]) >= int(os.environ["REPLICATION_TIMEOUT_SECONDS"]):
                metric("ReplicationTimeout")
                raise GateClosed("Replication verification deadline exceeded")
            record = get_record(f"RELEASE#{digest}")
            for region in (cfg["PRIMARY_REGION"], cfg["SECONDARY_REGION"]):
                ecr = client("ecr", region)
                try:
                    observed = image_digest(ecr, cfg["APPROVED_REPOSITORY"], {"imageTag": record["version"]})
                except ecr.exceptions.ImageNotFoundException:
                    raise Pending("Replication not complete")
                if observed != digest:
                    raise GateClosed("Published or replicated digest mismatch")
            # Recheck source findings before making the two-region catalog eligible.
            scan_counts(cfg["STAGING_REPOSITORY"], digest, cfg)
            update(record["pk"], {"status": "RELEASED", "eligible": True, "released_at": timestamp()},
                   ~Attr("status").is_in(["BLOCKED", "WITHDRAWN"]))
            evidence(digest, "released", {"digest": digest, "version": record["version"],
                     "regions": [cfg["PRIMARY_REGION"], cfg["SECONDARY_REGION"]]})
            metric("ReleaseSucceeded")
            return {"status": "RELEASED"}
        if action == "fail":
            update(f"RELEASE#{digest}", {"status": "BLOCKED", "eligible": False,
                   "failure": event.get("reason", "Workflow failed"), "failed_at": timestamp()})
            evidence(digest, "blocked", event)
            metric("ReleaseBlocked")
            notify("AL2023 release blocked", {"digest": digest, "reason": event.get("reason")})
            return {"status": "BLOCKED"}
        raise GateClosed("Unknown operation")
    except Pending as exc:
        return {"status": "PENDING", "reason": str(exc)}
    except GateClosed as exc:
        return {"status": "REJECTED", "reason": str(exc)}


def request_rebuild(digest, cfg):
    # At most three automatic remediation builds per reviewed source revision,
    # at most one per day. An operator changes the source to renew this budget.
    pk = "CONTROL#rebuild#" + cfg["SOURCE_REVISION"]
    prior = get_record(pk) or {"attempts": 0, "last_attempt": 0}
    if int(prior["attempts"]) >= 3 or timestamp() - int(prior["last_attempt"]) < 86400:
        return
    token = hashlib.sha256(f"{pk}:{prior['attempts']}:{digest}".encode()).hexdigest()
    try:
        update(pk, {"attempts": int(prior["attempts"]) + 1, "last_attempt": timestamp()},
               Attr("attempts").not_exists() | Attr("attempts").eq(prior["attempts"]))
    except table().meta.client.exceptions.ConditionalCheckFailedException:
        return
    client("imagebuilder").start_image_pipeline_execution(imagePipelineArn=cfg["PIPELINE_ARN"], clientToken=token)


def monitor(event, context):
    cfg = settings()
    heartbeat = get_record("CONTROL#heartbeat") or {}
    metric("BuildHeartbeatMissing", int(timestamp() - int(heartbeat.get("last_build", 0)) > 8 * 86400))
    pages = table().meta.client.get_paginator("query").paginate(
        TableName=cfg["TABLE_NAME"], IndexName="kind", KeyConditionExpression=Key("kind").eq("RELEASE"))
    for page in pages:
        for release in page["Items"]:
            if release.get("status") != "RELEASED":
                continue
            digest = release["digest"]
            try:
                for region in (cfg["PRIMARY_REGION"], cfg["SECONDARY_REGION"]):
                    scan_counts(cfg["APPROVED_REPOSITORY"], digest, cfg, region)
            except (GateClosed, Pending) as exc:
                update(release["pk"], {"status": "WITHDRAWN", "eligible": False, "reason": str(exc)})
                evidence(digest, "withdrawn", {"reason": str(exc)})
                notify("AL2023 release withdrawn", {"digest": digest, "reason": str(exc)})
                metric("ReleaseWithdrawn")
                if isinstance(exc, GateClosed) and "Critical finding" in str(exc):
                    request_rebuild(digest, cfg)
    return {"checked": True}
