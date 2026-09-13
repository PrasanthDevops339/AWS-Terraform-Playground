"""Offline behavioral tests; AWS SDK boundaries are faked, no credentials needed."""
import copy
import importlib.util
import json
import logging
import os
from pathlib import Path
import signal
import sys
import time
import types
import unittest
from unittest.mock import Mock, patch

SOURCE = Path(__file__).parents[1] / "src/handler.py"
COMMAND = "11111111-1111-1111-1111-111111111111"
INSTANCE = "i-0123456789abcdef0"


class Config:
    def __init__(self, **kwargs):
        self.__dict__.update(kwargs)


class HandlerTests(unittest.TestCase):
    def setUp(self):
        self.clients = {name: Mock() for name in ("s3", "ssm", "ec2")}
        self.configs = {}
        def client(name, config):
            self.configs[name] = config
            return self.clients[name]
        boto3 = types.ModuleType("boto3")
        boto3.client = client
        config = types.ModuleType("botocore.config")
        config.Config = Config
        spec = importlib.util.spec_from_file_location("patch_handler", SOURCE)
        self.h = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {"boto3": boto3, "botocore": types.ModuleType("botocore"), "botocore.config": config}), patch.dict(os.environ, {
            "BUCKET_NAME": "central-test", "S3_PREFIX": "outcomes", "ENRICH": "true",
            "INCLUDE_INSTANCE_TAGS": "true", "KMS_KEY_ARN": "", "OBJECT_ACL": "",
        }):
            exec(compile(SOURCE.read_text(), str(SOURCE), "exec"), self.h.__dict__)
        self.h.LOG.setLevel(logging.CRITICAL)
        self.context = Mock()
        self.context.get_remaining_time_in_millis.return_value = 30000
        self.event = {
            "id": "22222222-2222-2222-2222-222222222222", "source": "aws.ssm",
            "detail-type": "EC2 Command Invocation Status-change Notification",
            "account": "222233334444", "region": "us-east-1", "time": "2026-09-08T12:00:00Z",
            "detail": {"command-id": COMMAND, "instance-id": INSTANCE,
                       "document-name": "AWS-RunPatchBaseline", "status": "Success"},
        }
        self.command = {"CommandId": COMMAND, "Parameters": {"Operation": ["Install"]},
                        "TargetCount": 2, "CompletedCount": 2, "ErrorCount": 1,
                        "MaxErrors": "0", "MaxConcurrency": "1"}
        self.clients['ssm'].list_commands.return_value = {"Commands": [self.command]}
        self.clients['ssm'].list_command_invocations.return_value = {
            "CommandInvocations": [self.invocation("Failed")]}
        self.clients['ssm'].describe_instance_information.return_value = {"InstanceInformationList": [{"PingStatus": "Online"}]}
        self.clients['ec2'].describe_instances.return_value = {"Reservations": [{"Instances": [
            {"InstanceId": INSTANCE, "Tags": [{"Key": "Owner", "Value": "operations"}]}]}]}

    def invocation(self, status):
        return {"CommandId": COMMAND, "InstanceId": INSTANCE, "StatusDetails": status,
                "CommandPlugins": [{"Name": "Windows"}, {"Name": "Linux"}]}

    def invoke(self, event=None):
        result = self.h.handler(event or self.event, self.context)
        return json.loads(self.clients['s3'].put_object.call_args.kwargs['Body']), result

    def test_install_success_uses_command_operation_and_no_tag_lookup(self):
        rec, _ = self.invoke()
        self.assertEqual((rec['schema_version'], rec['operation'], rec['patch_outcome']), (2, 'Install', 'patched'))
        self.assertEqual(rec['event_id'], self.event['id'])
        self.clients['ssm'].list_command_invocations.assert_not_called()
        self.clients['ec2'].describe_instances.assert_not_called()

    def test_scan_success_is_scanned(self):
        self.command['Parameters']['Operation'] = ['Scan']
        rec, _ = self.invoke()
        self.assertEqual(rec['patch_outcome'], 'scanned')
        self.clients['ec2'].describe_instances.assert_not_called()

    def test_operation_from_event_skips_ssm_on_success(self):
        self.event['detail']['parameters'] = {'Operation': ['Scan']}
        rec, _ = self.invoke()
        self.assertEqual(rec['patch_outcome'], 'scanned')
        self.clients['ssm'].list_commands.assert_not_called()

    def test_unknown_operation_never_claims_patched(self):
        self.h.ENRICH = False
        rec, _ = self.invoke()
        self.assertEqual((rec['operation'], rec['patch_outcome'], rec['status']), ('unknown', 'unknown', 'Success'))

    def test_aggregate_multistep_status_and_request_shape(self):
        self.event['detail']['status'] = 'Failed'
        self.clients['ssm'].list_command_invocations.return_value = {'CommandInvocations': [self.invocation('Terminated')]}
        rec, _ = self.invoke()
        self.assertEqual((rec['patch_outcome'], rec['status_details']), ('not-attempted', 'Terminated'))
        self.clients['ssm'].list_command_invocations.assert_called_once_with(CommandId=COMMAND, InstanceId=INSTANCE, Details=False)
        self.clients['ssm'].get_command_invocation.assert_not_called()
        self.assertEqual(rec['target_count'], 2)
        self.assertEqual(rec['tag_owner'], 'operations')

    def test_empty_and_nonterminal_invocations_are_retried(self):
        self.event['detail']['status'] = 'Failed'
        self.clients['ssm'].list_command_invocations.side_effect = [
            {'CommandInvocations': []}, {'CommandInvocations': [self.invocation('In Progress')]},
            {'CommandInvocations': [self.invocation('Terminated')]},
        ]
        with patch.object(self.h.time, 'sleep'):
            rec, _ = self.invoke()
        self.assertEqual(rec['status_details'], 'Terminated')
        self.assertEqual(self.clients['ssm'].list_command_invocations.call_count, 3)

    def test_lookup_filters_out_another_instance(self):
        self.event['detail']['status'] = 'Failed'
        other = self.invocation('Terminated')
        other['InstanceId'] = 'i-00000000000000000'
        self.clients['ssm'].list_command_invocations.return_value = {'CommandInvocations': [other]}
        with patch.object(self.h.time, 'sleep'):
            rec, _ = self.invoke()
        self.assertEqual(rec['patch_outcome'], 'unknown')

    def test_cancellation_is_not_proof_of_nonexecution(self):
        self.event['detail']['status'] = 'Cancelled'
        self.clients['ssm'].list_command_invocations.return_value = {'CommandInvocations': [self.invocation('Cancelled')]}
        rec, _ = self.invoke()
        self.assertEqual(rec['patch_outcome'], 'unknown')

    def test_explicit_nondelivery_without_enrichment(self):
        self.h.ENRICH = False
        for status in ['Terminated', 'Undeliverable', 'DeliveryTimedOut', 'Delivery Timed Out', 'InvalidPlatform', 'Invalid Platform', 'AccessDenied', 'Access Denied']:
            with self.subTest(status=status):
                self.event['detail']['status'] = status
                rec, _ = self.invoke()
                self.assertEqual(rec['patch_outcome'], 'not-attempted')

    def test_coarse_failure_without_details_is_unknown(self):
        self.h.ENRICH = False
        for status in ['Failed', 'TimedOut', 'Cancelled']:
            self.event['detail']['status'] = status
            rec, _ = self.invoke()
            self.assertEqual(rec['patch_outcome'], 'unknown')

    def test_confirmed_failure_and_execution_timeout(self):
        self.event['detail']['status'] = 'Failed'
        rec, _ = self.invoke()
        self.assertEqual(rec['patch_outcome'], 'failed')
        self.clients['ec2'].describe_instances.assert_not_called()
        self.h.ENRICH = False
        self.event['detail']['status'] = 'ExecutionTimedOut'
        rec, _ = self.invoke()
        self.assertEqual(rec['patch_outcome'], 'failed')

    def test_enrichment_failure_still_writes(self):
        self.event['detail']['status'] = 'Failed'
        for method in [self.clients['ssm'].list_commands, self.clients['ssm'].list_command_invocations,
                       self.clients['ssm'].describe_instance_information, self.clients['ec2'].describe_instances]:
            method.side_effect = RuntimeError('service unavailable')
        with patch.object(self.h.time, 'sleep'):
            rec, _ = self.invoke()
        self.assertEqual(rec['patch_outcome'], 'unknown')
        self.clients['s3'].put_object.assert_called_once()

    def test_deadline_interrupts_slow_enrichment_and_is_cleared_before_s3(self):
        self.h.ENRICHMENT_SECONDS = 0.03
        self.h.CALL_SECONDS = 0.001
        self.clients['ssm'].list_commands.side_effect = lambda **kw: time.sleep(0.3)
        self.clients['s3'].put_object.side_effect = lambda **kw: time.sleep(0.04)
        started = time.monotonic()
        rec, _ = self.invoke()
        self.assertLess(time.monotonic() - started, 0.25)
        self.assertEqual(rec['patch_outcome'], 'unknown')
        self.assertEqual(signal.getitimer(signal.ITIMER_REAL)[0], 0)

    def test_remaining_runtime_reserves_twenty_seconds(self):
        self.context.get_remaining_time_in_millis.return_value = 19000
        rec, _ = self.invoke()
        self.clients['ssm'].list_commands.assert_not_called()
        self.assertEqual(rec['patch_outcome'], 'unknown')

    def test_sdk_retries_and_timeouts_are_bounded(self):
        self.assertEqual(self.configs['ssm'].retries['total_max_attempts'], 1)
        self.assertEqual((self.configs['ssm'].connect_timeout, self.configs['ssm'].read_timeout), (1, 2))
        self.assertEqual(self.configs['s3'].retries['total_max_attempts'], 3)

    def test_cache_is_local_bounded_and_expires(self):
        self.invoke()
        self.invoke()
        self.assertEqual(self.clients['ssm'].list_commands.call_count, 1)
        self.h._CMD_CACHE[COMMAND] = (time.monotonic() - 1, self.command)
        self.invoke()
        self.assertEqual(self.clients['ssm'].list_commands.call_count, 2)
        self.h._CMD_CACHE.clear()
        for i in range(128):
            self.h._CMD_CACHE[str(i)] = (0, {})
        self.h._command(COMMAND, time.monotonic() + 10)
        self.assertLessEqual(len(self.h._CMD_CACHE), 128)

    def test_empty_command_not_cached_and_retried(self):
        self.clients['ssm'].list_commands.side_effect = [{'Commands': []}, {'Commands': [self.command]}]
        with patch.object(self.h.time, 'sleep'):
            rec, _ = self.invoke()
        self.assertEqual(rec['patch_outcome'], 'patched')
        self.assertEqual(self.clients['ssm'].list_commands.call_count, 2)

    def test_canary_is_distinct_and_does_not_enrich(self):
        event = {**self.event, 'source': 'custom.patch-canary', 'detail-type': 'canary', 'detail': {}}
        rec, result = self.invoke(event)
        self.assertEqual((rec['record_type'], rec['patch_outcome']), ('canary', 'unknown'))
        self.assertNotIn('instance_id', rec)
        self.assertIsNone(rec['command_id'])
        self.assertIn('/canary_', result['key'])
        self.clients['ssm'].list_commands.assert_not_called()

    def test_command_summary_is_not_an_instance_outcome(self):
        self.event['detail-type'] = 'EC2 Command Status-change Notification'
        self.event['detail']['status'] = 'Failed'
        del self.event['detail']['instance-id']
        rec, _ = self.invoke()
        self.assertEqual(rec['record_type'], 'command')
        self.assertNotIn('instance_id', rec)
        self.assertEqual(rec['patch_outcome'], 'unknown')
        self.assertEqual(rec['target_count'], 2)

    def test_duplicate_delivery_has_stable_key_and_event_id(self):
        one, first = self.invoke()
        two, second = self.invoke(copy.deepcopy(self.event))
        self.assertEqual(first['key'], second['key'])
        self.assertEqual(one['event_id'], two['event_id'])
        self.assertIn('/222233334444/us-east-1/', first['key'])

    def test_kms_and_acl_headers(self):
        self.h.KMS_KEY_ARN = 'arn:aws:kms:us-east-1:111122223333:key/test'
        self.h.OBJECT_ACL = 'bucket-owner-full-control'
        self.invoke()
        args = self.clients['s3'].put_object.call_args.kwargs
        self.assertEqual(args['ServerSideEncryption'], 'aws:kms')
        self.assertEqual(args['SSEKMSKeyId'], self.h.KMS_KEY_ARN)
        self.assertEqual(args['ACL'], 'bucket-owner-full-control')
        self.assertTrue(args['Body'].endswith(b'\n'))

    def test_s3_failure_propagates(self):
        self.clients['s3'].put_object.side_effect = RuntimeError('AccessDenied')
        with self.assertRaisesRegex(RuntimeError, 'AccessDenied'):
            self.invoke()

    def test_bad_event_and_unwrapped_destination_fail(self):
        with self.assertRaises(ValueError):
            self.invoke({'requestPayload': self.event})
        for field in ('id', 'account', 'time', 'region'):
            event = copy.deepcopy(self.event)
            del event[field]
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.invoke(event)
        self.clients['s3'].put_object.assert_not_called()

    def test_tags_toggle_and_hybrid_instance(self):
        self.h.INCLUDE_TAGS = False
        self.event['detail']['status'] = 'Terminated'
        self.invoke()
        self.clients['ec2'].describe_instances.assert_not_called()
        self.h.INCLUDE_TAGS = True
        self.event['detail']['instance-id'] = 'mi-0123456789abcdef0'
        self.invoke()
        self.clients['ec2'].describe_instances.assert_not_called()


if __name__ == '__main__':
    unittest.main()
