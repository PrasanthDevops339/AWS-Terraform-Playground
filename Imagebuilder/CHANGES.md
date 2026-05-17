# DataSync Image Builder — What Changed

## Files Added

| File | Description |
|---|---|
| `main.tf` | Terraform resource that deploys the CloudFormation stack via `aws_cloudformation_stack` |
| `variables.tf` | Input variables for the Terraform module |
| `outputs.tf` | Exposes AMI ID, internal SSM parameter name, and pipeline ARN as Terraform outputs |
| `versions.tf` | Pins Terraform ≥ 1.5 and AWS provider ≥ 5.0 |

---

## AWS-DataSync-AMI.yaml — Changes

### Removed

- **`LatestAmiId` parameter** — was a hardcoded AMI ID that was never referenced by any resource in the template.

---

### Renamed / Updated

- **`LatestDatasyncAmi` → `DatasyncSsmPath`** — renamed for clarity; the parameter type remains `AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>` with default `/aws/service/datasync/ami`.  
  CloudFormation resolves the SSM path to the current AWS-published AMI ID at deploy and update time. The recipe's `ParentImage` was updated to reference this parameter.

---

### Added

- **`AWSTemplateFormatVersion: "2010-09-09"`** — explicit version declaration added to the template header.

- **`DataSyncAmiSsmParam` resource (`AWS::SSM::Parameter`)** — publishes the Operations-owned AMI ID produced by the `Image` resource to `/internal/amis/datasync/latest`. Downstream consumers reference this internal path instead of the AWS public parameter.

- **Source lineage tags** — the following tags were added to the `DistributionConfiguration` AMI tags and the `Image` resource in both `us-east-2` and `us-east-1`:
  - `SourceSsmParam: /aws/service/datasync/ami`
  - `SourceAccount: <AWS::AccountId>`
  - `ManagedBy: ImageBuilder`

- **New Outputs**
  - `InternalSsmParamName` — path of the internal SSM parameter holding the Operations-owned AMI ID.
  - `PipelineArn` — ARN of the Image Builder pipeline for scheduled refreshes.
  - Both new outputs include `Export` names for cross-stack references.

---

### Fixed

- **Security group egress CIDR** — changed from `10.0.0.0/0` (invalid CIDR) to `0.0.0.0/0` with port 443 only (HTTPS for SSM and S3 endpoints).

---

## How the SSM Reference Works

```
AWS public SSM parameter
/aws/service/datasync/ami
        │
        │  CloudFormation resolves at deploy/update time
        ▼
DatasyncSsmPath parameter (AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>)
        │
        │  Used as ParentImage in ImageRecipe
        ▼
Image Builder copies, renames, tags, and distributes the AMI
        │
        │  Resulting AMI ID written to
        ▼
/internal/amis/datasync/latest  ◄── downstream consumers reference this path
```

Re-running `terraform apply` picks up any new AMI that AWS publishes to the public parameter path — no manual AMI ID updates required.
