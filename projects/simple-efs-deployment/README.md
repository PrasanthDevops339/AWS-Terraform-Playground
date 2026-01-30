# Simple EFS Deployment

This Terraform project deploys an encrypted Amazon EFS file system using reusable modules from the `terraform-aws-efs` and `terraform-aws-kms` modules.

## Architecture

This deployment creates:

- **KMS Key**: Customer-managed KMS key for EFS encryption at rest
- **Security Group**: Controls network access to EFS mount targets (NFS port 2049)
- **EFS File System**: Encrypted file system with configurable performance settings
- **Mount Targets**: Deployed across multiple subnets for high availability

## Prerequisites

- Terraform >= 1.5.0
- AWS Provider >= 6.0.0
- Existing VPC with subnets
- AWS credentials configured

## Usage

### 1. Clone and Configure

```bash
cd projects/simple-efs-deployment

# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
vim terraform.tfvars
```

### 2. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

### 3. Mount the EFS File System

After deployment, mount the EFS on your EC2 instances:

```bash
# Install NFS client (Amazon Linux 2)
sudo yum install -y nfs-utils

# Create mount point
sudo mkdir -p /mnt/efs

# Mount using the DNS name (from terraform output)
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport <efs-dns-name>:/ /mnt/efs
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `aws_region` | AWS region for deployment | `string` | `"us-east-2"` |
| `environment` | Environment name | `string` | `"dev"` |
| `project_name` | Name of the project | `string` | `"simple-efs"` |
| `vpc_name` | Name tag of the VPC | `string` | `"ins-dev-vpc-use2"` |
| `subnet_name_filter` | Filter pattern for subnets | `string` | `"*-data-*"` |
| `allowed_cidrs` | CIDR blocks allowed to access EFS | `list(string)` | `["10.0.0.0/16"]` |
| `enable_backup` | Enable EFS backup policy | `bool` | `true` |
| `tags` | Additional tags | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `efs_id` | The ID of the EFS file system |
| `efs_arn` | The ARN of the EFS file system |
| `efs_dns_name` | The DNS name for mounting |
| `efs_mount_target_ids` | IDs of mount targets |
| `kms_key_arn` | ARN of the encryption key |
| `security_group_id` | ID of the security group |
| `mount_command` | Example mount command |

## Module Dependencies

This project uses the following local modules:

- `../../Terrafrom-AWS-Prasanth/terraform-aws-kms` - KMS key management
- `../../Terrafrom-AWS-Prasanth/terraform-aws-efs` - EFS file system

## Security Considerations

- EFS is encrypted at rest using a customer-managed KMS key
- Encryption in transit can be enforced via mount options
- Security group restricts access to specified CIDR blocks only
- Backup policy is enabled by default

## Lifecycle Policy

The EFS is configured with intelligent tiering:
- Files transition to Infrequent Access (IA) after 30 days of no access
- Files transition back to Standard storage class upon first access

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Note**: The KMS key has a 7-day deletion window by default.
