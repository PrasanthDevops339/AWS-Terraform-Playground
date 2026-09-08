# Resources and responsibilities

The default Lambda deployment creates **26 resources**, including its IAM role
and common permissions policy. Each additional region with `create_writer_role=false`
creates **24 resources**; two regions sharing the role create **50 total** resources
per member account. A disabled SSM rule still exists as a resource.
Turning the canary off removes its rule, target and Lambda permission.

| Count per region | Resource | Purpose |
|---|---|---|
| 4 | EventBridge rules | Three SSM patterns plus optional manual canary. |
| 4 | EventBridge targets | One Lambda target per rule, each with the target DLQ. |
| 4 | Shared-module Lambda permissions | Permit only the configured rules to invoke the writer. |
| 1 | Shared-module Lambda function | Python 3.13, handler.handler, 128 MB, 30-second timeout. |
| 1 | Shared-module package S3 object | Regional zip; hash changes redeploy the function. |
| 4 | Package bucket + public block + ownership + encryption | Member-account deployment artifacts, distinct from the central archive. |
| 1 | CloudWatch log group | Explicit retention and optional local log CMK. |
| 1 | Regional IAM inline policy | Writes only this log group and Lambda failure queue. |
| 2 | Shared-module SQS queues | Fourteen-day target delivery DLQ and async failure destination. |
| 1 | Target queue policy | Grants EventBridge SendMessage for exact rules in this account. |
| 1 | Lambda async invoke configuration | Two function-error retries; six-hour maximum event age; on-failure destination. |

With `create_writer_role=true`, the module also creates one IAM role and one
common inline policy authorizing the central outcomes prefix, selected central
CMK and enabled SSM/EC2 enrichment calls. The primary Lambda deployment owns
those two resources; further regions reuse the role. Shared source modules are
consumed unchanged.

No central S3 bucket/policy/notification, KMS key/policy, ingestion service,
Splunk server, custom metric, alarm or notification service is created.
Terraform data sources and outputs do not add managed resources to this count.
