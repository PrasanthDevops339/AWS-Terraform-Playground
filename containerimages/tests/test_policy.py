import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import check_plan
import preflight
import validate_enterprise_inputs


class PolicyTests(unittest.TestCase):
    def plan(self, kind, values, actions=None):
        return {"resource_changes": [{"type": kind, "address": "module.factory.builder", "change": {
            "after": values, "actions": actions or ["create"]}}]}

    def test_mutable_repository_rejected(self):
        self.assertTrue(check_plan.evaluate(self.plan("aws_ecr_repository", {"image_tag_mutability": "MUTABLE"})))

    def test_builder_cannot_write_approved_repository(self):
        policy = {"Statement": [{"Effect": "Allow", "Action": ["ecr:PutImage"],
                    "Resource": "arn:aws:ecr:us-east-2:123456789012:repository/golden/test/al2023-base"}]}
        self.assertTrue(check_plan.evaluate(self.plan("aws_iam_role_policy", {"policy": json.dumps(policy)})))

    def test_privileged_publisher_rejected(self):
        self.assertTrue(check_plan.evaluate(self.plan("aws_codebuild_project", {"environment": [{"privileged_mode": True}]})))

    def test_replacements_require_migration_review(self):
        self.assertTrue(check_plan.evaluate(self.plan("aws_dynamodb_table", {}, ["delete", "create"])))

    def test_reviewed_test_ca_and_repo_config(self):
        fixtures = Path(__file__).parent / "fixtures"
        validate_enterprise_inputs.validate(fixtures / "ca.pem", fixtures / "enterprise.repo")

    def test_private_key_is_rejected_before_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "key.pem"
            path.write_text("-----BEGIN PRIVATE KEY-----")
            with self.assertRaises(ValueError):
                validate_enterprise_inputs.validate(path, path)

    def test_repository_signature_bypass_is_rejected(self):
        fixtures = Path(__file__).parent / "fixtures"
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "bad.repo"
            path.write_text((fixtures / "enterprise.repo").read_text().replace("gpgcheck=1", "gpgcheck=0"))
            with self.assertRaises(ValueError):
                validate_enterprise_inputs.validate(fixtures / "ca.pem", path)

    def test_scan_filter_matching(self):
        self.assertTrue(preflight.matches("golden/*", "golden/test/al2023-base"))
        self.assertFalse(preflight.matches("golden/*", "staging/test/al2023-base"))


if __name__ == "__main__":
    unittest.main()
