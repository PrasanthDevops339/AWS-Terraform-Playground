import copy
import datetime as dt
import json
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, patch

import boto3
from moto import mock_aws
from botocore.stub import Stubber

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "runtime"))
import factory
import promote

DIGEST = "sha256:" + "a" * 64
OTHER = "sha256:" + "b" * 64
ENV = {
    "AWS_ACCESS_KEY_ID": "testing", "AWS_SECRET_ACCESS_KEY": "testing", "AWS_DEFAULT_REGION": "us-east-2",
    "ACCOUNT_ID": "123456789012", "PRIMARY_REGION": "us-east-2", "SECONDARY_REGION": "us-east-1",
    "STAGING_REPOSITORY": "staging/test/al2023-base", "APPROVED_REPOSITORY": "golden/test/al2023-base",
    "TABLE_NAME": "test-releases", "EVIDENCE_BUCKET": "test-evidence", "FACTORY_NAME": "test",
    "PIPELINE_ARN": "arn:aws:imagebuilder:us-east-2:123456789012:image-pipeline/test-al2023",
    "STATE_MACHINE_ARN": "arn:aws:states:us-east-2:123456789012:stateMachine:test-release",
    "RELEASE_SERIES": "1.0", "SOURCE_REVISION": "c" * 40,
    "ALERT_TOPIC_ARN": "arn:aws:sns:us-east-2:123456789012:test-alerts",
    "SCAN_TIMEOUT_SECONDS": "3600", "REPLICATION_TIMEOUT_SECONDS": "7200",
}


class Base(unittest.TestCase):
    def setUp(self):
        self.environment = patch.dict(os.environ, ENV)
        self.environment.start()
        self.aws = mock_aws()
        self.aws.start()
        factory.client.cache_clear()
        factory.table.cache_clear()
        self.cfg = factory.settings()
        boto3.client("dynamodb").create_table(TableName=ENV["TABLE_NAME"],
            KeySchema=[{"AttributeName": "pk", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "pk", "AttributeType": "S"}], BillingMode="PAY_PER_REQUEST")
        factory.table().put_item(Item={"pk": "RELEASE#" + DIGEST, "digest": DIGEST,
                                      "status": "CANDIDATE", "build_arn": "test-build"})

    def tearDown(self):
        factory.client.cache_clear()
        factory.table.cache_clear()
        self.aws.stop()
        self.environment.stop()

    def scan_response(self, counts=None, complete=True, status="ACTIVE"):
        findings = {"findingSeverityCounts": counts if counts is not None else {}}
        if complete:
            findings["imageScanCompletedAt"] = dt.datetime.now(dt.timezone.utc)
        return {"registryId": ENV["ACCOUNT_ID"], "repositoryName": ENV["STAGING_REPOSITORY"],
                "imageId": {"imageDigest": DIGEST}, "imageScanStatus": {"status": status},
                "imageScanFindings": findings}

    def counts(self, response=None, findings=None):
        ecr = factory.client("ecr")
        inspector = Mock()
        inspector.get_paginator.return_value.paginate.return_value = findings or [{"findings": []}]
        original = factory.client
        with Stubber(ecr) as stub:
            stub.add_response("describe_image_scan_findings", response or self.scan_response(),
                {"repositoryName": ENV["STAGING_REPOSITORY"], "imageId": {"imageDigest": DIGEST}, "maxResults": 100})
            with patch.object(factory, "client", side_effect=lambda service, region=None: inspector if service == "inspector2" else original(service, region)):
                result = factory.scan_counts(ENV["STAGING_REPOSITORY"], DIGEST, self.cfg)
        return result, inspector


class ScanTests(Base):
    def test_completed_zero_omitted_critical_passes(self):
        result, inspector = self.counts()
        self.assertEqual(result["CRITICAL"], 0)
        filters = inspector.get_paginator.return_value.paginate.call_args.kwargs["filterCriteria"]
        self.assertEqual({v["value"] for v in filters["findingStatus"]}, {"ACTIVE", "SUPPRESSED"})
        self.assertEqual(filters["ecrImageHash"][0]["value"], DIGEST)

    def test_active_without_completion_blocks(self):
        with self.assertRaises(factory.Pending):
            self.counts(self.scan_response(complete=False))

    def test_event_supplies_completion_when_api_timestamp_absent(self):
        factory.table().put_item(Item={"pk": factory.scan_record_key("us-east-2", ENV["STAGING_REPOSITORY"], DIGEST), "critical": 0})
        result, _ = self.counts(self.scan_response(complete=False))
        self.assertEqual(result["CRITICAL"], 0)

    def test_summary_critical_blocks_even_before_findings_catch_up(self):
        with self.assertRaises(factory.GateClosed):
            self.counts(self.scan_response({"CRITICAL": 1}))

    def test_critical_on_later_page_blocks(self):
        with self.assertRaises(factory.GateClosed):
            self.counts(findings=[{"findings": [{"severity": "HIGH"}]}, {"findings": [{"severity": "CRITICAL", "status": "SUPPRESSED", "fixAvailable": "NO"}]}])

    def test_high_is_reported_not_blocked(self):
        result, _ = self.counts(findings=[{"findings": [{"severity": "HIGH"}]}])
        self.assertEqual(result["HIGH"], 1)

    def test_unknown_coverage_states_fail_closed(self):
        for status in ("FAILED", "UNSUPPORTED_IMAGE", "SCAN_ELIGIBILITY_EXPIRED", "COMPLETE", "FINDINGS_UNAVAILABLE"):
            with self.subTest(status=status), self.assertRaises(factory.GateClosed):
                self.counts(self.scan_response(status=status))

    def test_pending_states_wait(self):
        for status in ("PENDING", "IN_PROGRESS"):
            with self.subTest(status=status), self.assertRaises(factory.Pending):
                self.counts(self.scan_response(status=status))

    def test_wrong_account_or_digest_rejected(self):
        response = self.scan_response()
        response["registryId"] = "999999999999"
        with self.assertRaises(factory.GateClosed):
            self.counts(response)
        response = self.scan_response()
        response["imageId"]["imageDigest"] = OTHER
        with self.assertRaises(factory.GateClosed):
            self.counts(response)

    def test_missing_summary_does_not_mean_zero(self):
        response = self.scan_response()
        del response["imageScanFindings"]["findingSeverityCounts"]
        with self.assertRaises(factory.Pending):
            self.counts(response)

    def test_inspector_filter_schema_and_pagination(self):
        inspector = factory.client("inspector2")
        filters = {"awsAccountId": [{"comparison": "EQUALS", "value": ENV["ACCOUNT_ID"]}],
                   "ecrImageRepositoryName": [{"comparison": "EQUALS", "value": ENV["STAGING_REPOSITORY"]}],
                   "ecrImageHash": [{"comparison": "EQUALS", "value": DIGEST}],
                   "findingStatus": [{"comparison": "EQUALS", "value": s} for s in ("ACTIVE", "SUPPRESSED")]}
        ecr = factory.client("ecr")
        with Stubber(inspector) as ins, Stubber(ecr) as ec:
            ec.add_response("describe_image_scan_findings", self.scan_response())
            ins.add_response("list_findings", {"findings": [], "nextToken": "page2"}, {"filterCriteria": filters})
            ins.add_response("list_findings", {"findings": []}, {"filterCriteria": filters, "nextToken": "page2"})
            self.assertEqual(factory.scan_counts(ENV["STAGING_REPOSITORY"], DIGEST, self.cfg)["CRITICAL"], 0)
            ins.assert_no_pending_responses()


class ReleaseTests(Base):
    def test_versions_start_at_zero_and_retries_are_idempotent(self):
        self.assertEqual(factory.allocate_version(DIGEST, self.cfg), "1.0.0")
        self.assertEqual(factory.allocate_version(DIGEST, self.cfg), "1.0.0")
        factory.table().put_item(Item={"pk": "RELEASE#" + OTHER})
        self.assertEqual(factory.allocate_version(OTHER, self.cfg), "1.0.1")

    def test_failed_release_retry_requires_fresh_gate_and_retains_version(self):
        factory.update("RELEASE#" + DIGEST, {"status": "BLOCKED", "version": "1.0.7"})
        with patch.object(factory, "verified_build", return_value=DIGEST), patch.object(factory, "scan_counts", return_value={"CRITICAL": 0}) as scan, patch.object(factory, "evidence", return_value="evidence.json"):
            result = factory.evaluate(DIGEST, self.cfg)
        self.assertEqual(result["version"], "1.0.7")
        self.assertEqual(factory.get_record("RELEASE#" + DIGEST)["status"], "CANDIDATE")
        scan.assert_called_once()

    def test_withdrawn_release_cannot_be_reactivated_by_retry(self):
        factory.update("RELEASE#" + DIGEST, {"status": "WITHDRAWN"})
        with self.assertRaises(factory.GateClosed):
            factory.evaluate(DIGEST, self.cfg)

    def test_conditional_race_returns_winning_assignment(self):
        real_update = factory.update
        def competing_write(pk, fields, condition):
            real_update(pk, {"version": "1.0.9"})
            real_update(pk, fields, condition)
        with patch.object(factory, "update", side_effect=competing_write):
            self.assertEqual(factory.allocate_version(DIGEST, self.cfg), "1.0.9")

    def test_scan_deadline_prevents_late_acceptance(self):
        with patch.object(factory, "evaluate") as evaluate:
            result = factory.control({"action": "evaluate", "digest": DIGEST, "started_at": factory.timestamp() - 3601}, None)
            self.assertEqual(result["status"], "REJECTED")
            evaluate.assert_not_called()

    def test_replication_deadline(self):
        result = factory.control({"action": "replication", "digest": DIGEST, "started_at": "2020-01-01T00:00:00Z"}, None)
        self.assertEqual(result["status"], "REJECTED")

    def test_wrong_build_digest_never_allocates_version(self):
        with patch.object(factory, "verified_build", return_value=OTHER), patch.object(factory, "allocate_version") as allocate:
            with self.assertRaises(factory.GateClosed):
                factory.evaluate(DIGEST, self.cfg)
            allocate.assert_not_called()

    def test_critical_candidate_never_allocates_version(self):
        with patch.object(factory, "verified_build", return_value=DIGEST), patch.object(factory, "scan_counts", side_effect=factory.GateClosed("Critical")), patch.object(factory, "allocate_version") as allocate:
            with self.assertRaises(factory.GateClosed):
                factory.evaluate(DIGEST, self.cfg)
            allocate.assert_not_called()

    def test_replication_mismatch_never_sets_eligibility(self):
        factory.update("RELEASE#" + DIGEST, {"version": "1.0.0"})
        with patch.object(factory, "image_digest", side_effect=[DIGEST, OTHER]):
            result = factory.control({"action": "replication", "digest": DIGEST, "started_at": dt.datetime.now(dt.timezone.utc).isoformat()}, None)
        self.assertEqual(result["status"], "REJECTED")
        self.assertFalse(factory.get_record("RELEASE#" + DIGEST).get("eligible", False))

    def test_rebuild_cooldown_and_budget(self):
        imagebuilder = Mock()
        with patch.object(factory, "client", return_value=imagebuilder):
            factory.request_rebuild(DIGEST, self.cfg)
            factory.request_rebuild(DIGEST, self.cfg)
        imagebuilder.start_image_pipeline_execution.assert_called_once()
        factory.update("CONTROL#rebuild#" + ENV["SOURCE_REVISION"], {"attempts": 3, "last_attempt": 0})
        imagebuilder.reset_mock()
        with patch.object(factory, "client", return_value=imagebuilder):
            factory.request_rebuild(DIGEST, self.cfg)
        imagebuilder.start_image_pipeline_execution.assert_not_called()


class EventTests(Base):
    def event(self, when="2026-09-10T12:00:00Z", critical=0):
        return {"id": "event-1", "time": when, "account": ENV["ACCOUNT_ID"], "region": "us-east-2",
                "source": "aws.inspector2", "detail-type": "Inspector2 Scan", "detail": {
                    "scan-status": "INITIAL_SCAN_COMPLETE", "image-digest": DIGEST,
                    "repository-name": f"arn:aws:ecr:us-east-2:{ENV['ACCOUNT_ID']}:repository/{ENV['STAGING_REPOSITORY']}",
                    "finding-severity-counts": {"CRITICAL": critical}}}

    def test_scan_can_arrive_before_build_and_duplicate_is_safe(self):
        event = self.event()
        factory.ingest(event, None)
        factory.ingest(event, None)
        key = factory.scan_record_key("us-east-2", ENV["STAGING_REPOSITORY"], DIGEST)
        self.assertEqual(factory.get_record(key)["critical"], 0)

    def test_old_clean_event_cannot_overwrite_new_critical_event(self):
        factory.ingest(self.event("2026-09-10T12:00:01Z", 1), None)
        factory.ingest(self.event(), None)
        key = factory.scan_record_key("us-east-2", ENV["STAGING_REPOSITORY"], DIGEST)
        self.assertEqual(factory.get_record(key)["critical"], 1)

    def test_foreign_event_is_rejected(self):
        event = self.event()
        event["account"] = "999999999999"
        with self.assertRaises(factory.GateClosed):
            factory.ingest(event, None)

    def test_repository_arn_must_match_event_region(self):
        event = self.event()
        event["region"] = "us-east-1"
        with self.assertRaises(factory.GateClosed):
            factory.ingest(event, None)


class PublisherTests(Base):
    def worker(self, config=None, existing=None):
        ecr = factory.client("ecr")
        calls = []
        def observe(*args):
            calls.append(args)
            if len(calls) == 1 and existing is None:
                raise ecr.exceptions.ImageNotFoundException({"Error": {"Code": "ImageNotFoundException"}}, "DescribeImages")
            return existing or DIGEST
        config = config or {"architecture": "amd64", "os": "linux", "config": {"User": "10001:10001"}}
        with Stubber(ecr) as stub, patch.object(factory, "evaluate", return_value={"version": "1.0.0"}), patch.object(factory, "image_digest", side_effect=observe), patch.object(factory, "scan_counts", return_value={"CRITICAL": 0}), patch.object(factory, "evidence"), patch.object(promote.subprocess, "check_output", return_value=json.dumps(config)), patch.object(promote.subprocess, "run") as run:
            stub.add_response("get_authorization_token", {"authorizationData": [{"authorizationToken": "QVdTOnRlc3Q="}]})
            promote.promote(DIGEST)
            return run.call_args_list

    def test_copy_uses_scanned_digest_and_preserves_it(self):
        calls = self.worker()
        self.assertEqual(len(calls), 1)
        argv = calls[0].args[0]
        self.assertIn("--preserve-digests", argv)
        self.assertIn("@" + DIGEST, argv[-2])
        self.assertTrue(argv[-1].endswith(":1.0.0"))
        self.assertNotIn("QVdTOnRlc3Q=", " ".join(argv))

    def test_matching_existing_version_does_not_copy_again(self):
        self.assertEqual(self.worker(existing=DIGEST), [])

    def test_root_image_fails_final_configuration_check(self):
        with self.assertRaises(factory.GateClosed):
            self.worker(config={"architecture": "amd64", "os": "linux", "config": {"User": "0"}})

    def test_arm_image_cannot_enter_x86_release(self):
        with self.assertRaises(factory.GateClosed):
            self.worker(config={"architecture": "arm64", "os": "linux", "config": {"User": "10001:10001"}})

    def test_gate_failure_never_copies(self):
        with patch.object(factory, "evaluate", side_effect=factory.GateClosed("Critical")), patch.object(promote.subprocess, "run") as run:
            with self.assertRaises(factory.GateClosed):
                promote.promote(DIGEST)
            run.assert_not_called()

    def test_tag_conflict_never_copies(self):
        with patch.object(factory, "evaluate", return_value={"version": "1.0.0"}), patch.object(factory, "image_digest", return_value=OTHER), patch.object(promote.subprocess, "run") as run:
            with self.assertRaises(factory.GateClosed):
                promote.promote(DIGEST)
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
