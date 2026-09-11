"""CodeBuild publisher: verifies the gate itself and never executes candidate code."""
import json
import os
import subprocess
import tempfile
import sys

from boto3.dynamodb.conditions import Attr
import factory


def promote(digest):
    digest = factory.digest_checked(digest)
    cfg = factory.settings()
    # Repeat authorization in the trusted worker. A caller-supplied PASS or tag
    # is never accepted; resolve the assigned version from the release ledger.
    accepted = factory.evaluate(digest, cfg)
    version = accepted["version"]
    ecr = factory.client("ecr")
    try:
        existing = factory.image_digest(ecr, cfg["APPROVED_REPOSITORY"], {"imageTag": version})
    except ecr.exceptions.ImageNotFoundException:
        existing = None
    if existing and existing != digest:
        raise factory.GateClosed("Immutable version belongs to a different digest")
    registry = f"{cfg['ACCOUNT_ID']}.dkr.ecr.{cfg['PRIMARY_REGION']}.amazonaws.com"
    with tempfile.TemporaryDirectory() as directory:
        auth = os.path.join(directory, "auth.json")
        token = ecr.get_authorization_token()["authorizationData"][0]["authorizationToken"]
        # Tokens remain in a permission-restricted temporary auth file, never argv/logs.
        with open(auth, "w", encoding="utf-8") as handle:
            json.dump({"auths": {registry: {"auth": token}}}, handle)
        os.chmod(auth, 0o600)
        config = json.loads(subprocess.check_output([
            "skopeo", "inspect", "--config", "--authfile", auth,
            f"docker://{registry}/{cfg['STAGING_REPOSITORY']}@{digest}"], text=True))
        if (config.get("architecture") != "amd64" or config.get("os") != "linux"
                or config.get("config", {}).get("User") != "10001:10001"):
            raise factory.GateClosed("Final image must be Linux amd64 with USER 10001:10001")
        # Authentication/config inspection can take time; refresh the verdict at the copy boundary.
        factory.scan_counts(cfg["STAGING_REPOSITORY"], digest, cfg)
        if not existing:
            subprocess.run(["skopeo", "copy", "--preserve-digests", "--authfile", auth,
                f"docker://{registry}/{cfg['STAGING_REPOSITORY']}@{digest}",
                f"docker://{registry}/{cfg['APPROVED_REPOSITORY']}:{version}"], check=True)
    if factory.image_digest(ecr, cfg["APPROVED_REPOSITORY"], {"imageTag": version}) != digest:
        raise factory.GateClosed("Post-copy digest mismatch")
    factory.update(f"RELEASE#{digest}", {"published_at": factory.timestamp()},
                   ~Attr("status").is_in(["WITHDRAWN", "BLOCKED"]))
    factory.evidence(digest, "published", {"digest": digest, "version": version})


def main():
    promote(os.environ["CANDIDATE_DIGEST"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
