"""
Script to generate the CloudTrail Cost Spike Executive Summary Word document.
Run: python generate_executive_summary_doc.py
Output: CloudTrail_Cost_Spike_Executive_Summary.docx in the same directory
"""

from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
import os


def set_cell_shading(cell, color_hex):
    from lxml import etree
    shading = cell._element.get_or_add_tcPr()
    shading_elem = etree.SubElement(shading, qn('w:shd'))
    shading_elem.set(qn('w:fill'), color_hex)
    shading_elem.set(qn('w:val'), 'clear')


def add_styled_table(doc, headers, rows, col_widths=None, header_color='2E74B5'):
    table = doc.add_table(rows=1 + len(rows), cols=len(headers))
    table.style = 'Table Grid'
    table.alignment = WD_TABLE_ALIGNMENT.CENTER

    for i, header in enumerate(headers):
        cell = table.rows[0].cells[i]
        cell.text = header
        for paragraph in cell.paragraphs:
            for run in paragraph.runs:
                run.bold = True
                run.font.size = Pt(10)
                run.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
        set_cell_shading(cell, header_color)

    for r, row_data in enumerate(rows):
        for c, val in enumerate(row_data):
            cell = table.rows[r + 1].cells[c]
            cell.text = str(val)
            for paragraph in cell.paragraphs:
                for run in paragraph.runs:
                    run.font.size = Pt(10)
            if r % 2 == 1:
                set_cell_shading(cell, 'DEEAF6')

    if col_widths:
        for i, width in enumerate(col_widths):
            for row in table.rows:
                row.cells[i].width = Inches(width)

    return table


def add_section_rule(doc):
    """Add a light horizontal divider paragraph."""
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(2)
    return p


def main():
    doc = Document()

    # -------------------------------------------------------------------------
    # Title block
    # -------------------------------------------------------------------------
    title = doc.add_heading('CloudTrail Cost Spike', level=0)
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER

    subtitle = doc.add_paragraph()
    subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = subtitle.add_run('Executive Summary')
    run.font.size = Pt(16)
    run.bold = True
    run.font.color.rgb = RGBColor(0x2E, 0x74, 0xB5)

    doc.add_paragraph()

    meta_headers = ['Field', 'Value']
    meta_rows = [
        ['Period', 'February 5-17, 2026'],
        ['Cost Increase', '~600% peak above baseline'],
        ['Security Impact', 'None — logging functioned correctly throughout'],
        ['Primary Fix Status', 'Applied February 17, 2026'],
        ['Open Items', '2 items remain — see bottom of this report'],
    ]
    add_styled_table(doc, meta_headers, meta_rows, col_widths=[2.0, 4.5])

    doc.add_paragraph()

    # -------------------------------------------------------------------------
    # Section 1: What Happened
    # -------------------------------------------------------------------------
    doc.add_heading('What Happened', level=1)
    doc.add_paragraph(
        'AWS CloudTrail costs increased by approximately 600% beginning February 5-6, 2026, '
        'and continued at an elevated level on subsequent days through mid-February.'
    )
    doc.add_paragraph(
        'The spike was confirmed across two cost drivers in AWS Cost Explorer:'
    )
    for item in [
        'Paid management event recording — AWS charges for API activity logs beyond the free baseline.',
        'CloudTrail Insights anomaly detection charges — a separate charge triggered when AWS '
        'detects unusually high API activity volumes.',
    ]:
        doc.add_paragraph(item, style='List Bullet')

    # -------------------------------------------------------------------------
    # Section 2: What Caused It
    # -------------------------------------------------------------------------
    doc.add_heading('What Caused It', level=1)
    doc.add_paragraph(
        'The root cause was a compliance reporting automation job that runs on a scheduled '
        'basis inside AWS ECS (Elastic Container Service). This job scans all AWS accounts '
        'in the organization for non-compliant resources and produces reports for remediation teams.'
    )
    doc.add_paragraph('Two compounding issues drove the cost:')

    # Issue 1
    doc.add_heading('Issue 1 — Design Flaw in the Automation Code (Active on Every Run)', level=2)
    doc.add_paragraph(
        'The job was making one database lookup call for every non-compliant resource it processed, '
        'rather than looking up each account once and reusing the result for the rest of the run.'
    )
    doc.add_paragraph(
        'With thousands of non-compliant resources spread across hundreds of accounts, this '
        'generated thousands of unnecessary API calls per run — where only 50-100 were needed. '
        'Every one of those calls is recorded as a paid CloudTrail event.'
    )
    p = doc.add_paragraph()
    run = p.add_run('This issue was present on every scheduled run, not just February 5-6.')
    run.bold = True

    doc.add_paragraph()

    # Issue 2
    doc.add_heading('Issue 2 — Job Ran for ~12 Continuous Hours on Feb 5-6 (Worst-Case Amplifier)', level=2)
    doc.add_paragraph(
        'A normal run of this job completes in a fraction of that time. On February 5-6, '
        'the job ran for approximately 12 hours without stopping or timing out.'
    )
    doc.add_paragraph(
        'Because the unnecessary database calls happen on every resource iteration, a 12-hour '
        'run produced roughly 12x the normal event volume — pushing the total far above the '
        'free-tier threshold and into paid territory across both active CloudTrail trails.'
    )
    doc.add_paragraph(
        'The exact reason the job ran for 12 hours is still under investigation. Likely '
        'contributors include a larger-than-normal result set, or internal API rate-limiting '
        'causing the job to stall and retry repeatedly.'
    )

    doc.add_paragraph()

    # Issue 3
    doc.add_heading('Issue 3 — CloudTrail Insights Charges Compounding (Secondary Cost Driver)', level=2)
    doc.add_paragraph(
        'CloudTrail Insights is a monitoring feature that detects unusual API call patterns '
        'and charges separately when it triggers. Because the automation\'s API call volume '
        'was abnormally high on February 5 and again on February 11-13, Insights fired on '
        'both occasions.'
    )
    doc.add_paragraph(
        'This created a compounding charge: billed once for generating the events, and again '
        'for CloudTrail detecting that the volume was abnormal.'
    )

    # -------------------------------------------------------------------------
    # Section 3: Why It Persisted
    # -------------------------------------------------------------------------
    doc.add_heading('Why It Persisted Beyond February 5-6', level=1)
    doc.add_paragraph(
        'The design flaw in the code was active on every subsequent scheduled run. Although '
        'no other run lasted 12 hours, each normal run still generated significantly more '
        'paid events than it should — visible as recurring cost spikes across the February window.'
    )

    doc.add_paragraph()

    pattern_headers = ['Period', 'Relative Cost', 'Driver']
    pattern_rows = [
        ['Feb 1-3', 'Baseline', 'Normal'],
        ['Feb 5-6', 'PEAK — ~600% above baseline', '12-hour run + design flaw + Insights triggered'],
        ['Feb 7-9', 'Elevated', 'Design flaw active on normal-length runs'],
        ['Feb 9-10', 'Near baseline', '—'],
        ['Feb 11-13', 'High — 2nd largest spike', 'Design flaw + Insights triggered again'],
        ['Feb 14-16', 'Near baseline', '—'],
        ['Feb 17', 'Slightly elevated', 'Next scheduled run'],
    ]
    add_styled_table(doc, pattern_headers, pattern_rows, col_widths=[1.2, 2.3, 3.0])

    # -------------------------------------------------------------------------
    # Section 4: What Has Been Fixed
    # -------------------------------------------------------------------------
    doc.add_heading('What Has Been Fixed', level=1)

    p = doc.add_paragraph()
    run = p.add_run(
        'The code defect — the unnecessary per-resource database call — has been remediated '
        'as of February 17, 2026.'
    )
    run.bold = True

    doc.add_paragraph(
        'The fix adds a result cache so each account is looked up exactly once per run, '
        'regardless of how many non-compliant resources it contains. This reduces the excess '
        'API call volume by an estimated 50-200x per run and will prevent the recurring '
        'elevated cost pattern on future scheduled runs.'
    )
    doc.add_paragraph(
        'No functionality was changed — the job produces identical compliance reports. '
        'Only the number of redundant API calls was eliminated.'
    )

    # -------------------------------------------------------------------------
    # Section 5: What Remains Open
    # -------------------------------------------------------------------------
    doc.add_heading('What Remains Open', level=1)

    open_headers = ['Item', 'Priority', 'Action Required']
    open_rows = [
        ['Investigate why the Feb 5-6 run lasted ~12 hours',
         'High',
         'Review ECS task logs; add a maximum runtime limit so the job cannot run indefinitely'],
        ['Review CloudTrail Insights configuration',
         'High',
         'Confirm with security/compliance team whether Insights is required; '
         'disabling it eliminates the secondary cost component entirely'],
        ['Audit both active CloudTrail trails for event overlap',
         'Medium',
         'Verify the two trails are not recording the same events twice — '
         'the second copy of any event is fully paid'],
    ]
    add_styled_table(doc, open_headers, open_rows, col_widths=[2.0, 0.8, 3.7],
                     header_color='C55A11')

    # -------------------------------------------------------------------------
    # Section 6: Business Impact Summary
    # -------------------------------------------------------------------------
    doc.add_heading('Business Impact Summary', level=1)

    impact_headers = ['Dimension', 'Assessment']
    impact_rows = [
        ['Cost impact', 'High — ~600% peak spike, recurring elevated cost through Feb 17'],
        ['Security impact', 'None — CloudTrail logging functioned correctly throughout'],
        ['Compliance impact', 'None — no data loss, no rule misconfiguration'],
        ['Operational impact', 'Low — automation produced correct output; only efficiency was affected'],
        ['Recurrence risk', 'Reduced — primary code fix applied Feb 17; residual risk from open items above'],
    ]
    add_styled_table(doc, impact_headers, impact_rows, col_widths=[2.0, 4.5],
                     header_color='375623')

    doc.add_paragraph()

    footer = doc.add_paragraph()
    footer.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = footer.add_run(
        'Prepared: February 17, 2026  |  '
        'Detailed technical RCA: CloudTrail_Cost_Spike_RCA.md / .docx'
    )
    run.font.size = Pt(9)
    run.font.color.rgb = RGBColor(0x59, 0x56, 0x59)
    run.italic = True

    # -------------------------------------------------------------------------
    # Save
    # -------------------------------------------------------------------------
    output_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        'CloudTrail_Cost_Spike_Executive_Summary.docx'
    )
    doc.save(output_path)
    print(f'Word document saved to: {output_path}')


if __name__ == '__main__':
    main()

