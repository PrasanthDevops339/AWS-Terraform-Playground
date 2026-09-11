"""Start a trusted workflow retry; never edits findings, versions or ledger verdicts."""
import argparse
import json
import re
import time

import boto3
from botocore.config import Config


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--state-machine-arn", required=True)
    parser.add_argument("--digest", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", args.digest):
        raise ValueError("Supply an exact sha256 image digest")
    region = args.state_machine_arn.split(":")[3]
    result = boto3.client("stepfunctions", region_name=region,
        config=Config(retries={"mode": "standard", "total_max_attempts": 4})).start_execution(
        stateMachineArn=args.state_machine_arn,
        name=f"retry-{args.digest[7:31]}-{int(time.time())}",
        input=json.dumps({"digest": args.digest, "started_at": int(time.time())}))
    print(result["executionArn"])


if __name__ == "__main__":
    main()
