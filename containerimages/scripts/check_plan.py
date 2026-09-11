"""Deployment-plan policy checks, including IAM publication boundaries."""
import json
import sys


def evaluate(plan):
    errors = []
    for change in plan.get("resource_changes", []):
        kind = change["type"]
        after = change["change"].get("after") or {}
        actions = change["change"]["actions"]
        address = change["address"]
        if "delete" in actions:
            errors.append(f"{address}: deletion/replacement requires a separately reviewed migration")
        if not after:
            continue
        if kind == "aws_ecr_repository":
            if after.get("image_tag_mutability") != "IMMUTABLE":
                errors.append(f"{address}: version tags must be immutable")
            if not all(c.get("encryption_type") == "KMS" for c in after.get("encryption_configuration", [])):
                errors.append(f"{address}: require KMS encryption")
        if kind == "aws_codebuild_project" and any(e.get("privileged_mode") for e in after.get("environment", [])):
            errors.append(f"{address}: promotion cannot use privileged mode")
        if kind == "aws_imagebuilder_image_pipeline" and not all(c.get("image_tests_enabled") for c in after.get("image_tests_configuration", [])):
            errors.append(f"{address}: build tests must be enabled")
        if kind == "aws_vpc_security_group_egress_rule" and after.get("cidr_ipv4") == "0.0.0.0/0":
            errors.append(f"{address}: require approved egress destinations")
        if kind == "aws_iam_role_policy" and "builder" in address and isinstance(after.get("policy"), str):
            for statement in json.loads(after["policy"]).get("Statement", []):
                permissions = statement.get("Action", [])
                permissions = [permissions] if isinstance(permissions, str) else permissions
                if statement.get("Effect") == "Allow" and "ecr:PutImage" in permissions:
                    targets = statement.get("Resource", [])
                    targets = [targets] if isinstance(targets, str) else targets
                    if any(":repository/staging/" not in target or "*" in target for target in targets):
                        errors.append(f"{address}: builder writes must be restricted to a specific staging repository")
    return errors


def main():
    with open(sys.argv[1], encoding="utf-8") as handle:
        errors = evaluate(json.load(handle))
    for error in errors:
        print(error)
    if errors:
        raise SystemExit(1)
    print("Deployment plan policy checks passed; human review is still required.")


if __name__ == "__main__":
    main()
