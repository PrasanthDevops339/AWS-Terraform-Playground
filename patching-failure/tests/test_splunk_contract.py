"""Offline lookup/fixture contract checks, not a replacement for live SPL tests."""
import configparser
import csv
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).parents[1]


class SplunkContractTests(unittest.TestCase):
    def test_lookup_definition_and_action_mapping(self):
        props = configparser.ConfigParser(interpolation=None)
        props.read(ROOT / 'splunk/props.conf')
        transforms = configparser.ConfigParser(interpolation=None)
        transforms.read(ROOT / 'splunk/transforms.conf')
        name = props['aws:ssm:patch:outcome']['LOOKUP-patch_outcome_action'].split()[0]
        filename = transforms[name]['filename']
        with (ROOT / 'splunk' / filename).open() as stream:
            rows = list(csv.DictReader(stream))
        mapping = {(r['patch_outcome'], r['status_details']): r['action'] for r in rows}
        self.assertEqual(len(mapping), len(rows), 'Duplicate keys would make lookup results ambiguous.')
        self.assertIn('OUTPUTNEW action AS recommended_action', props['aws:ssm:patch:outcome']['LOOKUP-patch_outcome_action'])
        self.assertIn('installs nothing', mapping['scanned', 'Success'])
        self.assertIn('may have started', mapping['unknown', 'Cancelled'])
        self.assertIn('Do not infer', mapping['unknown', 'Success'])

    def test_same_command_different_instances_keep_their_own_stdout(self):
        # Read the grouping fields from the shipped SPL, then apply them to the
        # fixtures. This checks the data contract, not Splunk's query execution.
        query = (ROOT / 'splunk/failure_stdout.spl').read_text()
        keys = re.search(r' AS stdout BY ([^\n]+)', query).group(1).split()
        self.assertEqual(keys, ['account', 'region', 'command_id', 'instance_id'])
        records = json.loads((ROOT / 'tests/fixtures/splunk-records.json').read_text())
        groups = {}
        for rec in records:
            if rec['sourcetype'].endswith(':outcome') and rec['record_type'] != 'invocation':
                continue
            group = groups.setdefault(tuple(rec[k] for k in keys), {'stdout': set(), 'events': set()})
            if rec['sourcetype'].endswith(':stdout'):
                group['stdout'].add(rec['_raw'])
            else:
                group['events'].add(rec['event_id'])
        self.assertEqual(len(groups), 2)
        for key, group in groups.items():
            self.assertEqual(group['stdout'], {'stdout for ' + key[-1]})
            self.assertEqual(len(group['events']), 1, 'Redeliveries must not count twice.')

    def test_fleet_query_uses_latest_install_and_excludes_summaries(self):
        query = (ROOT / 'splunk/fleet_install_state.spl').read_text()
        self.assertIn('operation="Install"', query)
        self.assertIn('record_type="invocation"', query)
        self.assertIn('dedup account region event_id', query)
        self.assertIn('dedup account region instance_id', query)
        self.assertIn('sort 0 - _time - _indextime', query)
        summary = (ROOT / 'splunk/command_summary.spl').read_text()
        self.assertIn('record_type="invocation"', summary)
        self.assertIn('dedup account region command_id instance_id', summary)


if __name__ == '__main__':
    unittest.main()
