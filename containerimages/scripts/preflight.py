"""Read-only preflight for registry ownership and scan/replication coverage."""
import argparse
import fnmatch
import json
import sys

import boto3
from botocore.config import Config


def matches(filter_value, repository):
    # ECR enhanced-scan filters without * use substring matching.
    return fnmatch.fnmatchcase(repository, filter_value) if "*" in filter_value else filter_value in repository


def check(account, factory, primary, secondary):
    sdk = Config(retries={"mode": "standard", "total_max_attempts": 4}, connect_timeout=5, read_timeout=20)
    if boto3.client("sts", config=sdk).get_caller_identity()["Account"] != account:
        raise ValueError("Authenticated account differs from deployment account")
    staging, approved = f"staging/{factory}/al2023-base", f"golden/{factory}/al2023-base"
    clients = {r: boto3.client("ecr", region_name=r, config=sdk) for r in (primary, secondary)}
    for region, repositories in ((primary, [staging, approved]), (secondary, [approved])):
        config = clients[region].get_registry_scanning_configuration()["scanningConfiguration"]
        if config.get("scanType") != "ENHANCED":
            raise ValueError(f"{region}: enhanced scanning is not configured")
        for repo in repositories:
            if not any(rule["scanFrequency"] == "CONTINUOUS_SCAN" and any(
                    matches(f["filter"], repo) for f in rule["repositoryFilters"]) for rule in config["rules"]):
                raise ValueError(f"{region}: continuous scanning does not cover {repo}")
    rules = clients[primary].describe_registry().get("replicationConfiguration", {}).get("rules", [])
    replicated = False
    for rule in rules:
        prefixes = [f["filter"] for f in rule.get("repositoryFilters", [])]
        if not prefixes or any(staging.startswith(prefix) for prefix in prefixes):
            raise ValueError("An existing replication rule includes staging; narrow it before building")
        if any(approved.startswith(prefix) for prefix in prefixes):
            replicated |= any(d["region"] == secondary and d["registryId"] == account for d in rule["destinations"])
    if not replicated:
        raise ValueError("Approved image replication to the secondary Region is missing")
    return {"account": account, "factory": factory, "registry_preflight": "passed"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--account-id", required=True)
    parser.add_argument("--factory", required=True)
    parser.add_argument("--primary-region", default="us-east-2")
    parser.add_argument("--secondary-region", default="us-east-1")
    args = parser.parse_args()
    print(json.dumps(check(args.account_id, args.factory, args.primary_region, args.secondary_region)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
