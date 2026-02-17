"""
Script to generate the CloudTrail Cost Spike RCA Word document.
Run: python generate_cloudtrail_cost_spike_doc.py
Output: CloudTrail_Cost_Spike_RCA.docx in the same directory
"""

from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
import os


def set_cell_shading(cell, color_hex):
    """Apply background shading to a table cell."""
    from lxml import etree
    shading = cell._element.get_or_add_tcPr()
    shading_elem = etree.SubElement(shading, qn('w:shd'))
    shading_elem.set(qn('w:fill'), color_hex)
    shading_elem.set(qn('w:val'), 'clear')


def add_styled_table(doc, headers, rows, col_widths=None):
    """Create a formatted table with header shading."""
    table = doc.add_table(rows=1 + len(rows), cols=len(headers))
    table.style = 'Table Grid'
    table.alignment = WD_TABLE_ALIGNMENT.CENTER

    for i, header in enumerate(headers):
        cell = table.rows[0].cells[i]
        cell.text = header
        for paragraph in cell.paragraphs:
            for run in paragraph.runs:
                run.bold = True
                run.font.size = Pt(9)
                run.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
        set_cell_shading(cell, '2E74B5')

    for r, row_data in enumerate(rows):
        for c, val in enumerate(row_data):
            cell = table.rows[r + 1].cells[c]
            cell.text = str(val)
            for paragraph in cell.paragraphs:
                for run in paragraph.runs:
                    run.font.size = Pt(9)
            if r % 2 == 1:
                set_cell_shading(cell, 'DEEAF6')

    if col_widths:
        for i, width in enumerate(col_widths):
            for row in table.rows:
                row.cells[i].width = Inches(width)

    return table


def add_code_block(doc, code_text):
    p = doc.add_paragraph()
    run = p.add_run(code_text)
    run.font.name = 'Courier New'
    run.font.size = Pt(8)
    return p


def main():
    doc = Document()

    # -------------------------------------------------------------------------
    # Title
    # -------------------------------------------------------------------------
    title = doc.add_heading('CloudTrail Cost Spike — Root Cause Analysis & Remediation', level=0)
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER

    subtitle = doc.add_paragraph()
    subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = subtitle.add_run('config_aggregator.py ECS Task  |  Recurring Elevated Cost  |  Feb 2026')
    run.font.size = Pt(11)
    run.font.color.rgb = RGBColor(0x59, 0x56, 0x59)

    doc.add_paragraph()

    meta_headers = ['Field', 'Value']
    meta_rows = [
        ['Incident Period', 'February 5–6, 2026 (recurring on every scheduled ECS run)'],
        ['Affected Component', 'config_aggregator.py ECS Task — every run; worst case ~12 hours on Feb 5-6'],
        ['Primary Cost Driver', 'USE2-PaidEventsRecorded + USE2-InsightsEvents'],
        ['Cost Increase', '~600% peak (Feb 5-6); recurring elevated cost on subsequent runs'],
        ['Confirmed Trigger', 'Uncached API calls active on every run; 12-hour outlier amplified Feb 5-6'],
        ['Secondary Driver', 'CloudTrail Insights triggering on abnormal API call volume'],
        ['Security Risk', 'Low — logging functioning correctly'],
    ]
    add_styled_table(doc, meta_headers, meta_rows, col_widths=[2.0, 4.5])

    # -------------------------------------------------------------------------
    # Section 1: What Happened
    # -------------------------------------------------------------------------
    doc.add_heading('1. What Happened', level=1)
    doc.add_paragraph(
        'CloudTrail costs increased by approximately 600% beginning February 5–6, 2026, '
        'with a recurring elevated pattern on subsequent scheduled ECS runs. Cost Explorer '
        'confirms two dominant cost drivers: USE2-PaidEventsRecorded and USE2-InsightsEvents.'
    )

    pattern_headers = ['Period', 'Approx Relative Cost', 'Spike Drivers']
    pattern_rows = [
        ['Feb 1-3', 'Baseline (~50-100)', 'Normal'],
        ['Feb 5-6', 'Peak (~1,300-1,400)', 'PaidEventsRecorded + InsightsEvents — 12-hour ECS run'],
        ['Feb 7-9', 'Elevated (~300-450)', 'PaidEventsRecorded — subsequent ECS runs'],
        ['Feb 9-10', 'Near baseline', '—'],
        ['Feb 11-13', 'High (~700-800)', 'PaidEventsRecorded + InsightsEvents — further ECS runs'],
        ['Feb 14-16', 'Near baseline', '—'],
        ['Feb 17', 'Slightly elevated', 'Next scheduled run'],
    ]
    add_styled_table(doc, pattern_headers, pattern_rows, col_widths=[1.2, 1.8, 3.5])

    doc.add_paragraph()
    doc.add_paragraph(
        'The spike was NOT caused by trail creation or a Config rule deployment. '
        'The Feb 5-6 worst-case spike was triggered by the ECS task running ~12 hours. '
        'However, the recurring elevated pattern on other days confirms the root cause is '
        'active on every normal scheduled run — the 12-hour outlier simply made it catastrophic.'
    )

    p = doc.add_paragraph()
    p.add_run('The USE2-InsightsEvents cost component:').bold = True
    doc.add_paragraph(
        'CloudTrail Insights monitors API call rates and charges when it detects abnormal volume. '
        'Its appearance on Feb 5 and Feb 11-13 means the ECS task generated enough API calls '
        'to trigger CloudTrail\'s own anomaly detection. This creates a compounding cost: '
        'charged once for PaidEventsRecorded, and again for InsightsEvents analysis on top.'
    )

    trail_headers = ['Trail Name', 'Scope']
    trail_rows = [
        ['aws-controltower-BaselineCloudTrail', 'Org-wide, Multi-Region'],
        ['aws-aft-CustomizationsCloudTrail', 'Org-wide, Multi-Region'],
    ]
    add_styled_table(doc, trail_headers, trail_rows, col_widths=[3.5, 3.0])

    # -------------------------------------------------------------------------
    # Section 2: Root Causes
    # -------------------------------------------------------------------------
    doc.add_heading('2. Why It Happened — Root Causes', level=1)

    # RC1
    doc.add_heading('Root Cause 1: ECS Task Ran ~12 Hours — Runtime Multiplier', level=2)
    doc.add_paragraph(
        'The config_aggregator.py ECS task ran for approximately 12 continuous hours on '
        'Feb 5–6 instead of completing in its expected shorter window. This is the primary '
        'trigger for the cost spike.'
    )
    doc.add_paragraph(
        'Because check_account() fires one uncached DynamoDB Query per resource and '
        'get_rule_description() fires paginated Config API calls per rule x account x region, '
        'the total management event count scales linearly with task runtime. A 12-hour run '
        'vs. a 1-hour run produces roughly 12x the API call volume — directly explaining '
        'the ~600% spike.'
    )
    p = doc.add_paragraph()
    run = p.add_run('Likely causes of the extended runtime (to be confirmed via ECS logs):')
    run.bold = True
    for item in [
        'A much larger non-compliant resource result set than typical (larger pagination loop).',
        'API throttling causing the built-in retry/sleep loop to stall '
        '(ThrottlingException -> time.sleep(3 * tries), up to 3 retries per call).',
        'get_rule_description() paginating over an unexpectedly large annotation result set.',
        'No task-level timeout or ECS stopTimeout configured, allowing the container to run indefinitely.',
    ]:
        doc.add_paragraph(item, style='List Bullet')

    # RC2
    doc.add_heading('Root Cause 2: check_account() Called Per Resource Without Caching', level=2)
    doc.add_paragraph(
        'In config_aggregator.py, the function check_account() queries DynamoDB on every '
        'non-compliant resource iteration inside the main processing loop. '
        'There is no caching on this function, unlike get_account_name_cached() which '
        'already uses an account_cache dict.'
    )
    add_code_block(doc, '# Line 428 — called inside the per-resource loop\nis_one_dot_zero = check_account(account_name)')
    doc.add_paragraph(
        'Every DynamoDB Query is a management event recorded to CloudTrail. Processing '
        '5,000 non-compliant resources across 50 accounts fires 5,000 DynamoDB Query '
        'calls per run instead of 50. Over a 12-hour run, this is amplified further.'
    )

    rc2_headers = ['Scenario', 'DynamoDB Calls per Run']
    rc2_rows = [
        ['Before fix (no cache)', '1 per resource (thousands)'],
        ['After fix (cached by account name)', '1 per unique account (50–100)'],
    ]
    add_styled_table(doc, rc2_headers, rc2_rows, col_widths=[3.0, 3.5])
    doc.add_paragraph()

    # RC3
    doc.add_heading(
        'Root Cause 3: get_rule_description() — Paginated Config API Calls Per Rule x Account x Region',
        level=2
    )
    doc.add_paragraph(
        'The cache key in get_rule_description() is (rule_name, account_id, region). '
        'Every unique combination triggers a GetAggregateComplianceDetailsByConfigRule '
        'paginator call, which may issue multiple API pages per cache miss.'
    )
    add_code_block(
        doc,
        '# Called inside per-resource, per-rule inner loop\n'
        'annotation = get_rule_description(rule.get(\'configRuleName\'), account_id, region, rule_ann)'
    )
    doc.add_paragraph(
        'At scale: 20 rules x 100 accounts x 5 regions = 10,000+ Config API calls per run, '
        'each a paid management event. Over a 12-hour extended run, cache misses accumulate '
        'and the paginator may stall on large result sets.'
    )

    # RC4
    doc.add_heading('Root Cause 4: boto3 Clients Created Inside Hot-Path Loops', level=2)
    doc.add_paragraph(
        'boto3 client objects are created inside functions or loops that execute on every '
        'iteration rather than once at module level.'
    )
    add_code_block(
        doc,
        '# get_rule_description() — line 195 — new client on every cache miss\n'
        'client = boto3.client(\'config\', region_name=REGION, config=Config(retries={...}))\n\n'
        '# S3 upload loop — line 492 — new client per account group\n'
        's3 = boto3.client(\'s3\', region_name=REGION)'
    )
    doc.add_paragraph(
        'If role chaining is in use, repeated client creation triggers sts:AssumeRole or '
        'sts:GetSessionToken calls — additional management events on every iteration.'
    )

    # -------------------------------------------------------------------------
    # Section 3: Timeline
    # -------------------------------------------------------------------------
    doc.add_heading('3. Timeline Correlation', level=1)

    timeline_headers = ['Date / Window', 'Event', 'CloudTrail Impact']
    timeline_rows = [
        ['Feb 1-3', 'Baseline normal operation', 'Normal management event volume'],
        ['Feb 5-6 (~12 hrs)',
         'ECS task ran continuously for ~12 hours',
         'Peak spike: uncached calls x 12-hour duration + Insights anomaly triggered'],
        ['Feb 7-9',
         'Subsequent scheduled ECS runs (normal duration)',
         'Still elevated — check_account() uncached on every run'],
        ['Feb 11-13',
         'Further scheduled ECS runs',
         'Second significant spike — Insights events triggered again'],
        ['Feb 14-16', 'Near baseline — smaller result set or no run', '—'],
        ['Feb 17', 'Next scheduled run', 'Smaller but still above pre-Feb-5 baseline'],
    ]
    add_styled_table(doc, timeline_headers, timeline_rows, col_widths=[1.2, 2.5, 2.8])

    doc.add_paragraph()
    doc.add_paragraph(
        'Key conclusion: The 12-hour run was the worst case, but recurring spikes on Feb 7-9 '
        'and Feb 11-13 confirm the code-level issues generate excess paid events on every run. '
        'Fixing only the ECS timeout without fixing the caching will reduce severity but not '
        'eliminate the elevated cost.'
    )

    # -------------------------------------------------------------------------
    # Section 4: Remediation
    # -------------------------------------------------------------------------
    doc.add_heading('4. Remediation', level=1)

    # Fix 1
    doc.add_heading('Fix 1 — Add ECS Task-Level Timeout and Alerting (Immediate)', level=2)
    doc.add_paragraph(
        'The 12-hour runtime was the core multiplier. Without a task timeout, the container '
        'ran indefinitely. Two controls prevent recurrence:'
    )
    p = doc.add_paragraph()
    p.add_run('A. Set an ECS stopTimeout and CloudWatch alarm on task duration:').bold = True
    add_code_block(
        doc,
        '# ECS task definition — container stop timeout\n'
        '{\n'
        '  "containerDefinitions": [{\n'
        '    "stopTimeout": 120\n'
        '  }]\n'
        '}'
    )
    doc.add_paragraph(
        'Add a CloudWatch alarm on ECS task RunningTaskCount duration to alert if a task '
        'is still running past its expected completion window.'
    )
    p = doc.add_paragraph()
    p.add_run('B. Add a script-level watchdog timeout inside config_aggregator.py:').bold = True
    add_code_block(
        doc,
        'import signal\n\n'
        'def _timeout_handler(signum, frame):\n'
        '    logger.error("Task exceeded maximum allowed runtime. Exiting.")\n'
        '    raise SystemExit(1)\n\n'
        '# Allow max 2 hours before hard exit\n'
        'signal.signal(signal.SIGALRM, _timeout_handler)\n'
        'signal.alarm(7200)'
    )

    # Fix 2
    doc.add_heading('Fix 2 — Add Cache to check_account() [IMPLEMENTED Feb 17, 2026]', level=2)
    doc.add_paragraph(
        'STATUS: Applied to config_aggregator.py on Feb 17, 2026. '
        'version_cache dict and check_account_cached() wrapper added at lines 252-260, '
        'following the same pattern as account_cache / get_account_name_cached(). '
        'The call site at line 428 was updated. The original check_account() is unchanged.'
    )
    add_code_block(
        doc,
        '# Add near the other caches (around line 241 in config_aggregator.py)\n'
        'version_cache = {}\n\n'
        'def check_account_cached(account_name):\n'
        '    if account_name not in version_cache:\n'
        '        version_cache[account_name] = check_account(account_name)\n'
        '    return version_cache[account_name]'
    )
    doc.add_paragraph('Replace the call at line 428:')
    add_code_block(
        doc,
        '# Before\n'
        'is_one_dot_zero = check_account(account_name)\n\n'
        '# After\n'
        'is_one_dot_zero = check_account_cached(account_name)'
    )
    doc.add_paragraph(
        'Expected reduction: DynamoDB Query calls drop from N-resources to N-unique-accounts '
        'per run. Typically a 50–200x reduction.'
    )

    # Fix 3
    doc.add_heading('Fix 3 — Move boto3 Clients Outside Loops', level=2)
    doc.add_paragraph(
        'Create clients once before the loop begins rather than per-iteration:'
    )
    add_code_block(
        doc,
        '# Move to module-level or before the for-loop\n'
        'config_client = boto3.client(\'config\', region_name=REGION, config=Config(retries={\'max_attempts\': 10}))\n'
        's3_client = boto3.client(\'s3\', region_name=REGION)'
    )

    # Fix 4
    doc.add_heading('Fix 4 — Validate Trail Overlap Configuration', level=2)
    doc.add_paragraph(
        'Verify both active trails are not double-recording the same management events. '
        'The first copy per trail is free; any additional copy is fully paid.'
    )
    add_code_block(
        doc,
        'aws cloudtrail get-trail --name aws-controltower-BaselineCloudTrail\n'
        'aws cloudtrail get-trail --name aws-aft-CustomizationsCloudTrail'
    )
    for item in [
        'Are both trails set to Read + Write management events?',
        'Are both Multi-Region?',
        'Do both have Organization trail scope?',
    ]:
        doc.add_paragraph(item, style='List Bullet')

    # Fix 5
    doc.add_heading('Fix 6 — Review CloudTrail Insights Configuration', level=2)
    doc.add_paragraph(
        'USE2-InsightsEvents appeared prominently on Feb 5 and Feb 11-13, meaning Insights is '
        'enabled on at least one trail and triggering on the elevated API call volumes. '
        'Insights charges $0.35 per 100,000 events analyzed.'
    )
    add_code_block(
        doc,
        '# Check which trails have Insights enabled\n'
        'aws cloudtrail get-insight-selectors --trail-name aws-controltower-BaselineCloudTrail\n'
        'aws cloudtrail get-insight-selectors --trail-name aws-aft-CustomizationsCloudTrail'
    )
    doc.add_paragraph(
        'If Insights is enabled for ApiCallRateInsight and there is no compliance requirement '
        'for it, disabling it will immediately eliminate the InsightsEvents cost component. '
        'If Insights must remain enabled, fix the underlying API call volume first (Fix 2). '
        'Once call volume normalizes, the Insights threshold will no longer be crossed.'
    )

    doc.add_heading('Fix 7 — Investigate Root Cause of 12-Hour Runtime', level=2)
    doc.add_paragraph(
        'Query CloudTrail and ECS logs for the Feb 5–6 window to identify where '
        'the task was spending its time:'
    )
    add_code_block(
        doc,
        '-- Athena: top API callers Feb 5–6\n'
        'SELECT useridentity.arn, eventsource, eventname, COUNT(*) AS event_count\n'
        'FROM cloudtrail_logs\n'
        'WHERE eventtime >= \'2026-02-05T00:00:00Z\'\n'
        '  AND eventtime <= \'2026-02-06T23:59:59Z\'\n'
        'GROUP BY useridentity.arn, eventsource, eventname\n'
        'ORDER BY event_count DESC\n'
        'LIMIT 50;'
    )
    doc.add_paragraph(
        'Cross-reference with ECS/CloudWatch task logs to confirm whether the delay was in '
        'the Config query pagination loop, get_rule_description() stalling, or '
        'ThrottlingException retry backoff.'
    )

    # -------------------------------------------------------------------------
    # Section 5: Future View — New Config Rule Deployments
    # -------------------------------------------------------------------------
    doc.add_heading('5. Future View — Deploying New Config Rules Safely', level=1)
    doc.add_paragraph(
        'Even without an extended ECS run, deploying Config rules into a large organization '
        'aggregator requires a controlled approach to avoid cost spikes and compliance noise. '
        'The following practices should be applied to all future rule deployments.'
    )

    # 5.1 Phased Deployment
    doc.add_heading('5.1 Stage Deployments by OU or Account Tier', level=2)
    doc.add_paragraph(
        'Never deploy a new Config rule org-wide simultaneously. Use a phased rollout:'
    )
    phase_headers = ['Phase', 'Scope', 'Purpose']
    phase_rows = [
        ['Phase 1', 'Sandbox / Dev OU (1–5 accounts)',
         'Validate rule logic and evaluation behavior'],
        ['Phase 2', 'Non-production OUs (10–20 accounts)',
         'Validate at scale, observe event volume'],
        ['Phase 3', 'Production OUs',
         'Full deployment with known event baseline'],
    ]
    add_styled_table(doc, phase_headers, phase_rows, col_widths=[1.0, 2.5, 3.0])
    doc.add_paragraph(
        'Each phase should run for at least one full aggregator evaluation cycle before expanding. '
        'Monitor ECS task duration at each phase — a longer-than-normal run after adding a '
        'new rule is an early warning sign of increased result set volume.'
    )

    # 5.2 Estimate Resource Scope
    doc.add_heading('5.2 Pre-Deployment: Estimate Resource Scope', level=2)
    doc.add_paragraph(
        'Before deploying, estimate the number of in-scope resources to anticipate evaluation '
        'volume and expected config_aggregator.py result set growth.'
    )
    add_code_block(
        doc,
        '-- AWS Config Advanced Query: count resources in scope\n'
        'SELECT resourceType, COUNT(*) AS resource_count\n'
        'FROM aws_config_configuration_snapshot\n'
        'WHERE resourceType = \'AWS::EC2::Volume\'\n'
        'GROUP BY resourceType;'
    )
    doc.add_paragraph(
        'Use this count to estimate the additional rows config_aggregator.py will need to '
        'process per run, and validate the expected ECS task duration before deploying org-wide.'
    )

    # 5.3 MaximumExecutionFrequency
    doc.add_heading('5.3 Use MaximumExecutionFrequency to Control Evaluation Rate', level=2)
    doc.add_paragraph(
        'For periodic rules (not change-triggered), set the maximum execution frequency '
        'to reduce ongoing event volume and aggregator result set size:'
    )
    freq_headers = ['Frequency', 'Use Case']
    freq_rows = [
        ['One_Hour', 'High-sensitivity security rules'],
        ['Three_Hours', 'Standard compliance rules'],
        ['Six_Hours', 'Low-urgency inventory rules'],
        ['TwentyFour_Hours', 'Cost-optimization or tagging rules'],
    ]
    add_styled_table(doc, freq_headers, freq_rows, col_widths=[2.0, 4.5])

    # 5.4 Narrow Scope
    doc.add_heading('5.4 Set Change-Triggered Scope Narrowly', level=2)
    doc.add_paragraph(
        'For change-triggered rules, explicitly define the Scope to the minimum required '
        'resource types. Broad or undefined scope means any resource change triggers '
        'evaluation, increasing both Config API volume and aggregator result set size.'
    )
    add_code_block(
        doc,
        '# Terraform — narrow scope to only EBS volumes\n'
        'resource "aws_config_config_rule" "ebs_encryption" {\n'
        '  name = "ebs-volume-encryption"\n\n'
        '  scope {\n'
        '    compliance_resource_types = ["AWS::EC2::Volume"]\n'
        '  }\n\n'
        '  source {\n'
        '    owner             = "AWS"\n'
        '    source_identifier = "ENCRYPTED_VOLUMES"\n'
        '  }\n'
        '}'
    )

    # 5.5 Monitor ECS Task Duration
    doc.add_heading('5.5 Monitor ECS Task Duration After Each Rule Deployment', level=2)
    doc.add_paragraph(
        'ECS task runtime is the direct cost multiplier identified in this incident. '
        'Establish a duration check as part of every Config rule deployment runbook:'
    )
    cost_steps = [
        'Record typical ECS task duration (baseline) before rule deployment.',
        'Deploy rule to Phase 1 scope.',
        'Monitor ECS task duration for the next 2–3 runs.',
        'If duration increases by more than 30%, investigate result set growth before Phase 2.',
        'Set a CloudWatch alarm on ECS task duration that pages on-call if exceeded.',
    ]
    for i, step in enumerate(cost_steps, 1):
        doc.add_paragraph(f'{i}. {step}')

    # 5.6 Decouple Remediation
    doc.add_heading('5.6 Separate Remediation Automation from Config Evaluation', level=2)
    doc.add_paragraph(
        'If a Config rule triggers automated remediation (SSM Automation, Lambda), each '
        'remediation action generates its own management events and may add to the '
        'non-compliant resource count that config_aggregator.py needs to process.'
    )
    for item in [
        'Deploy rule in Audit mode (report-only) first.',
        'Review non-compliant resource count and confirm expected aggregator result set size.',
        'Enable remediation as a separate, controlled step with rate limiting applied.',
    ]:
        doc.add_paragraph(item, style='List Bullet')

    # -------------------------------------------------------------------------
    # Section 6: Summary
    # -------------------------------------------------------------------------
    doc.add_heading('6. Summary', level=1)

    summary_headers = ['Finding', 'Severity', 'Remediation']
    summary_rows = [
        ['check_account() uncached -- recurred on every scheduled ECS run',
         'Critical',
         'FIXED -- version_cache + check_account_cached() applied Feb 17, 2026'],
        ['ECS task ran ~12 hours on Feb 5-6 -- worst-case runtime multiplier',
         'High',
         'Add ECS stopTimeout + CloudWatch duration alarm'],
        ['USE2-InsightsEvents compounding on high-volume runs',
         'High',
         'Audit Insights config; disable ApiCallRateInsight if not required'],
        ['get_rule_description() -- Config API calls at scale',
         'Medium',
         'Cache in place; verify hit rate and pagination depth'],
        ['boto3 clients created inside loops',
         'Low',
         'Move to module-level or before loop start'],
        ['Possible trail overlap (double-recording events)',
         'Medium',
         'Audit both trail configurations'],
        ['Root cause of 12-hour runtime not yet confirmed',
         'Medium',
         'Investigate ECS + CloudWatch logs for Feb 5-6 run'],
    ]
    add_styled_table(doc, summary_headers, summary_rows, col_widths=[2.5, 1.0, 3.0])

    doc.add_paragraph()

    # -------------------------------------------------------------------------
    # Section 7: Risk Level
    # -------------------------------------------------------------------------
    doc.add_heading('7. Risk Level', level=1)

    risk_headers = ['Risk Type', 'Level', 'Notes']
    risk_rows = [
        ['Ongoing cost risk', 'High',
         'check_account() fix applied -- remaining risk from ECS timeout gap + Insights events'],
        ['Security risk', 'Low',
         'CloudTrail logging is functioning correctly'],
        ['Compliance risk', 'Low',
         'No data loss or rule misconfiguration'],
    ]
    add_styled_table(doc, risk_headers, risk_rows, col_widths=[2.0, 1.0, 3.5])

    # -------------------------------------------------------------------------
    # Save
    # -------------------------------------------------------------------------
    output_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        'CloudTrail_Cost_Spike_RCA.docx'
    )
    doc.save(output_path)
    print(f'Word document saved to: {output_path}')


if __name__ == '__main__':
    main()
