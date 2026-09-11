# Cost controls and estimation inputs

No AWS billing data was queried and no monthly price estimate is claimed. Use current regional rates and measured pilot usage before approving a budget. Costs from this factory are separate from application workloads that consume its images.

| Driver | What to measure | Existing control |
|---|---|---|
| Image Builder EC2/EBS | Build/test instance hours, disk size and duration | Temporary capacity, encrypted gp3, cleanup on failure, weekly schedule opt-in |
| CodeBuild promotion | Worker minutes and image-transfer duration | Small worker, concurrency 1, bounded queue/build time |
| Inspector | Initial and subsequent image scans, retained covered images | Factory repository filters, candidate retention; preserve required continuous coverage |
| ECR | Compressed layers retained in both Regions and transfer | Staging expires after 14 days; untagged approved artifacts after 30 days |
| S3 | Evidence, build logs, automation packages and noncurrent versions | Evidence expiration and incomplete-upload cleanup |
| KMS | Regional keys and encryption API requests | Shared factory key where appropriate; regional key for replica ECR |
| Lambda/Step Functions | Polls, invocations, findings volume and release duration | Scan deadline, bounded retries, reserved concurrency without provisioned concurrency |
| CloudWatch | Log ingestion/storage, alarms, dashboard and metric dimensions | Explicit retention and bounded Factory dimension; digests stay in logs |
| Network | Existing NAT/proxy and interface endpoint usage | Reuse approved private connectivity; account for shared-network allocation |

On-demand DynamoDB is the initial choice for intermittent release traffic. Revisit capacity after measuring the pilot. Do not assume interface endpoints are always cheaper than NAT; fixed endpoint charges depend on the number of services and Availability Zones. S3/DynamoDB gateway endpoints may be useful within the existing network, but this repository does not modify its routes.

Approved version tags are retained to support downstream builds and rollback. Define an application-aware retirement process before adding automatic deletion of tagged releases. Versioned S3 automation objects and build logs also need an enterprise retention decision; monitor growth rather than deleting artifacts still referenced by deployment configurations.

To estimate monthly spend, export regional unit rates from the AWS Pricing Calculator or Price List API, collect pilot quantities per service, then calculate each line and total with a spreadsheet/script. Include both Regions, scanning after promotion/replication, failed builds and retries. Keep the rate date, source, currency and assumptions with the estimate. Do not infer cost from Terraform resource counts alone.

Use the supplied `Factory`, `Environment`, `Owner` and `ManagedBy` tags for allocation; activate relevant cost-allocation tags through the established billing-owner process. Connect the pilot to the existing account budget/anomaly-monitoring process before enabling the weekly schedule. Budget alerts notify; they do not cap AWS spending or replace the publication gate.

References: [AWS Pricing Calculator](https://calculator.aws/), [Inspector pricing](https://aws.amazon.com/inspector/pricing/), [ECR pricing](https://aws.amazon.com/ecr/pricing/), [CodeBuild pricing](https://aws.amazon.com/codebuild/pricing/).
