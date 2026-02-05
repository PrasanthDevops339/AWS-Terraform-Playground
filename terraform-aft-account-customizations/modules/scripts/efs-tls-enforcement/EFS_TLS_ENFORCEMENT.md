# EFS TLS Enforcement Lambda - Behavior Notes

This document explains what `efs_tls_enforcement.py` does, the decision paths it covers, and example (dummy) scenarios for each outcome.

## What the script does

- Receives an AWS Config custom rule event.
- Extracts the configuration item and resource identity.
- Ignores non-EFS resources and deleted resources with NOT_APPLICABLE.
- For EFS file systems, calls `DescribeFileSystemPolicy` and evaluates whether the policy denies EFS client actions when `aws:SecureTransport` is false.
- Submits a single evaluation back to AWS Config with COMPLIANT, NON_COMPLIANT, or NOT_APPLICABLE.

## Decision matrix

| Step | Condition | Compliance Type | Annotation | Notes |
| --- | --- | --- | --- | --- |
| 1 | Missing `configurationItem` or missing `resourceId` | NOT_APPLICABLE | Missing configuration item or resource ID in event | Event is malformed or incomplete. |
| 2 | `resourceType` is not `AWS::EFS::FileSystem` | NOT_APPLICABLE | Resource type {resource_type} is not evaluated by this rule | Rule only targets EFS file systems. |
| 3 | `configurationItemStatus` is `ResourceDeleted` | NOT_APPLICABLE | Resource has been deleted | Config item indicates deletion. |
| 4 | `DescribeFileSystemPolicy` returns empty `Policy` | NON_COMPLIANT | EFS file system has no policy defined | No policy attached. |
| 5 | `PolicyNotFound` exception | NON_COMPLIANT | EFS file system has no policy - TLS enforcement not configured | Explicit AWS API exception. |
| 6 | `FileSystemNotFound` exception | NON_COMPLIANT | EFS file system not found: {file_system_id} | EFS removed or ID invalid at evaluation time. |
| 7 | Policy found, but SecureTransport deny does not apply to EFS client actions | NON_COMPLIANT | EFS policy does not enforce TLS for EFS client actions (ClientMount/ClientWrite/ClientRootAccess) | Deny is missing or scoped incorrectly. |
| 8 | Policy found, SecureTransport deny applies to EFS client actions | COMPLIANT | EFS file system policy enforces TLS (aws:SecureTransport) for client actions | Desired policy present. |
| 9 | Any other error during evaluation | NON_COMPLIANT | Error evaluating EFS policy: {error} | Error message is clipped to Config limits. |

## Dummy scenarios (examples)

1) Missing configuration item
- Event contains `invokingEvent` but no `configurationItem` or no `resourceId`.
- Result: NOT_APPLICABLE
- Annotation: "Missing configuration item or resource ID in event"

2) Non-EFS resource
- Config sends an S3 bucket item (`AWS::S3::Bucket`).
- Result: NOT_APPLICABLE
- Annotation: "Resource type AWS::S3::Bucket is not evaluated by this rule"

3) EFS deleted
- `resourceType` is EFS, `configurationItemStatus` is `ResourceDeleted`.
- Result: NOT_APPLICABLE
- Annotation: "Resource has been deleted"

4) EFS exists, no policy
- `DescribeFileSystemPolicy` returns no Policy field.
- Result: NON_COMPLIANT
- Annotation: "EFS file system has no policy defined"

5) EFS exists, policy missing (PolicyNotFound)
- AWS returns `PolicyNotFound` for the file system.
- Result: NON_COMPLIANT
- Annotation: "EFS file system has no policy - TLS enforcement not configured"

6) EFS was deleted after Config capture
- Config item has a valid `resourceId`, but AWS API says `FileSystemNotFound`.
- Result: NON_COMPLIANT
- Annotation: "EFS file system not found: fs-12345678"

7) Policy exists but does not enforce TLS
- Policy has no `Deny` with `aws:SecureTransport` false for EFS client actions.
- Result: NON_COMPLIANT
- Annotation: "EFS policy does not enforce TLS for EFS client actions (ClientMount/ClientWrite/ClientRootAccess)"

8) Policy correctly enforces TLS
- Policy includes a `Deny` with `aws:SecureTransport` false and actions like `elasticfilesystem:Client*`.
- Result: COMPLIANT
- Annotation: "EFS file system policy enforces TLS (aws:SecureTransport) for client actions"

9) Unexpected error
- JSON policy is malformed or AWS API returns an unexpected error.
- Result: NON_COMPLIANT
- Annotation: "Error evaluating EFS policy: <error message>"
