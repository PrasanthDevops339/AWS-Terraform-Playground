# Splunk integration

The existing ingestion service remains owned by its current team. Verify that
it routes the sibling `patchingsolution-events/outcomes/` prefix into
`aws:ssm:patch:outcome` in the existing patching index. An existing stdout route
for `patchingsolution/` does not establish that the new prefix is included.
Do not create another Terraform S3 notification configuration.

Install the parsing stanza from `props.conf` on the appropriate parsing tier.
Install its `EVAL-lookup_status` and `LOOKUP-patch_outcome_action` settings,
`transforms.conf`, and `lookups/patch_outcome_action.csv` in the relevant search
app/search tier. The CSV file in this directory is copied into that app's
`lookups/` directory. The lookup maps `action` to `recommended_action` without
changing the raw `status_details`. See [Splunk automatic lookups](https://help.splunk.com/en/splunk-cloud-platform/manage-knowledge-objects/knowledge-management-manual/10.2.2510/use-the-configuration-files-to-configure-lookups/make-your-lookup-automatic).

The supplied searches use `aws_patching` as an example index:

| Search | Behavior |
|---|---|
| `instance_history.spl` | One instance's delivered terminal events, deduplicated by account, region and event ID. Replace the dummy filters. |
| `fleet_install_state.spl` | Latest **installation** result per account/region/instance. Later scans cannot overwrite installation history. This is an execution view, not a compliance view. |
| `failure_stdout.spl` | Correlates both sourcetypes by account, region, command ID and instance ID. Uses `stats` rather than a limited subsearch join. |
| `command_summary.spl` | Counts one latest invocation result per target. Excludes command records and canaries and separates scanned/unknown results. |

Both sourcetypes must extract `account`, `region`, `command_id`, and
`instance_id` consistently. If stdout currently exposes only `command_id`,
its owner must add the remaining extraction from its actual source path or
metadata. No sample stdout path is assumed. Outcome events without matching
stdout stay visible with an empty stdout field; stdout can arrive later.
`values(stdout)` collects distinct fragments; use the correlated IDs to open
raw stdout events when line order or repeated lines matter.

`schema_version=2` filters keep incompatible historical records out of the new
views. Unknown-operation success never becomes `patched`. Missing outcomes
remain possible because SSM delivery is best effort; no inventory or compliance
coverage is inferred from absence.

## Pilot acceptance in the existing Splunk deployment

1. Run a canary in each member/region and retain the EventId returned by
   `put-events`. Search `sourcetype="aws:ssm:patch:outcome" record_type=canary
   event_id="<EventId>"`; check schema 2 and the original event timestamp.
2. Run a representative Scan and Install; expect `scanned` and `patched` for
   successful invocations. Inspect the `recommended_action` values.
3. Check a command targeting two instances with different stdout; each result
   of `failure_stdout.spl` must contain only that instance's output.
4. Replay one received event and confirm instance/command counts are unchanged.
5. Compare fixture expectations in `tests/fixtures/splunk-records.json` with the
   searches. Local tests validate fixture correlation and configuration, not
   execution by the Splunk search engine; this live check remains required.
