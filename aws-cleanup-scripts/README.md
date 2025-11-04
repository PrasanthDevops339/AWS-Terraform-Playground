# AWS Resource Cleanup Scripts

This directory contains scripts for managing and cleaning up AWS resources, specifically ECR (Elastic Container Registry) images and AMIs (Amazon Machine Images).

## 📋 Overview

This directory provides the following scripts:

### 1. `aws_resource_cleanup.py`
Comprehensive resource management for ECR and AMI resources:
- **List ECR Images**: Get detailed information about all ECR images including repository name, tags, push dates, and sizes
- **List AMIs**: Get comprehensive details about all AMIs owned by your AWS account including creation dates, state, and metadata
- **Delete Old AMIs**: Safely delete old AMIs while retaining a specified number of the most recent ones

### 2. `delete_ecr_images.py` (Python)
Delete ECR images from a list of ARNs:
- **Delete by ARN**: Delete specific ECR images using their ARNs
- **Multi-region support**: Automatically detects and handles images across different regions
- **Dry-run mode**: Preview deletions before performing them
- **Profile support**: Use AWS CLI profiles for authentication

### 3. `delete_ecr_images.sh` (Shell)
Shell script version of ECR image deletion:
- **Bash-based**: Lightweight alternative using AWS CLI
- **Same functionality**: Delete ECR images by ARN with dry-run support
- **Color-coded output**: Enhanced readability with colored status messages
- **Cross-platform**: Works on Linux, macOS, and WSL

## 🚀 Quick Start

### Prerequisites

- Python 3.6 or higher
- AWS CLI configured with appropriate credentials
- IAM permissions for ECR and EC2 (AMI) operations

### Installation

1. Install Python dependencies:
```bash
cd aws-cleanup-scripts
pip install -r requirements.txt
```

2. Configure AWS credentials (if not already done):
```bash
aws configure
```

## 📖 Usage

### List ECR Images

List all ECR images with their metadata:

```bash
python aws_resource_cleanup.py \
  --aws-account-id 123456789012 \
  --action list-ecr
```

**Output includes:**
- Repository name and URI
- Image tags
- Push date and time
- Image size
- Image digest

### List AMIs

List all AMIs owned by your AWS account:

```bash
python aws_resource_cleanup.py \
  --aws-account-id 123456789012 \
  --action list-ami
```

**Output includes:**
- AMI ID
- AMI Name
- Creation date
- State (available, pending, failed, etc.)
- Architecture
- Description
- Tags

### Delete Old AMIs (Dry Run)

**Always test with dry-run first!** This simulates the deletion without actually removing any AMIs:

```bash
python aws_resource_cleanup.py \
  --aws-account-id 123456789012 \
  --action delete-ami \
  --keep 5 \
  --dry-run
```

This command will:
- List all AMIs sorted by creation date (newest first)
- Show which 5 AMIs would be kept
- Show which AMIs would be deleted
- **NOT actually delete anything** (dry-run mode)

### Delete Old AMIs (Live)

⚠️ **WARNING**: This will permanently delete AMIs. Use with caution!

```bash
python aws_resource_cleanup.py \
  --aws-account-id 123456789012 \
  --action delete-ami \
  --keep 5
```

**Example scenario**: If you have 400 AMIs and want to keep only the 5 most recent:
- Keeps: 5 newest AMIs
- Deletes: 395 oldest AMIs

The script will:
1. Display AMIs to keep and delete
2. Ask for confirmation (type "yes" to proceed)
3. Delete the old AMIs one by one
4. Show a summary of successful and failed deletions

### Specify AWS Region

By default, the script uses your configured AWS region. To use a different region:

```bash
python aws_resource_cleanup.py \
  --aws-account-id 123456789012 \
  --region us-west-2 \
  --action list-ami
```

## 🔒 Required IAM Permissions

The IAM user or role running these scripts needs the following permissions:

### For ECR Operations (Listing - aws_resource_cleanup.py)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:DescribeRepositories",
        "ecr:DescribeImages"
      ],
      "Resource": "*"
    }
  ]
}
```

### For ECR Image Deletion (delete_ecr_images.py/sh)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchDeleteImage",
        "ecr:DescribeImages",
        "ecr:ListImages"
      ],
      "Resource": "*"
    }
  ]
}
```

**Note**: For production use, it's recommended to restrict the `Resource` field to specific repository ARNs:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchDeleteImage",
        "ecr:DescribeImages",
        "ecr:ListImages"
      ],
      "Resource": "arn:aws:ecr:*:123456789012:repository/*"
    }
  ]
}
```

### For AMI Operations
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeImages",
        "ec2:DeregisterImage"
      ],
      "Resource": "*"
    }
  ]
}
```

## 📊 Example Outputs

### ECR Images List
```
================================================================================
ECR IMAGES REPORT
================================================================================

📦 Repository: my-app
   URI: 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app
   Total Images: 10
   1. Tags: v1.2.3, latest
      Pushed: 2024-10-20 15:30:00
      Size: 245.67 MB
      Digest: sha256:abc123def456...
```

### AMI List
```
================================================================================
AMI (Amazon Machine Images) REPORT
================================================================================

Total AMIs: 400
--------------------------------------------------------------------------------

1. AMI ID: ami-0abc123def456
   Name: my-app-v1.2.3
   Created: 2024-10-20T10:00:00.000Z
   State: available
   Architecture: x86_64
```

### AMI Deletion (Dry Run)
```
================================================================================
AMI DELETION (DRY RUN)
================================================================================

📋 Analysis:
   Total AMIs: 400
   AMIs to keep: 5
   AMIs to delete: 395

⚠️  DRY RUN MODE - No AMIs will be deleted

--------------------------------------------------------------------------------
AMIs TO KEEP (most recent):
--------------------------------------------------------------------------------
1. ami-0abc123 - my-app-v1.2.3 (Created: 2024-10-20T10:00:00.000Z)
2. ami-0def456 - my-app-v1.2.2 (Created: 2024-10-19T10:00:00.000Z)
...

✓ Dry run complete. 395 AMI(s) would be deleted in live mode.
```

## ⚙️ Command Line Options

| Option | Required | Description | Default |
|--------|----------|-------------|---------|
| `--aws-account-id` | Yes | Your AWS Account ID | - |
| `--action` | Yes | Action to perform: `list-ecr`, `list-ami`, or `delete-ami` | - |
| `--region` | No | AWS region to use | Current configured region |
| `--keep` | No | Number of most recent AMIs to keep (for delete-ami action) | 5 |
| `--dry-run` | No | Simulate deletion without actually deleting | False |

## 🛡️ Safety Features

1. **Dry Run by Default**: The delete operation prompts for confirmation
2. **Confirmation Required**: Must type "yes" to proceed with live deletion
3. **Sorted by Date**: AMIs are sorted by creation date (newest first) to ensure you keep the most recent
4. **Detailed Reporting**: Shows exactly what will be kept and deleted before proceeding
5. **Error Handling**: Continues processing even if individual deletions fail

## ⚠️ Important Notes

### About AMI Deletion
- **Deregistration only**: The script deregisters AMIs but does **NOT** automatically delete associated EBS snapshots
- **Snapshot cleanup**: You may want to manually delete associated snapshots to fully reclaim storage costs
- **Irreversible**: Once an AMI is deregistered, it cannot be recovered
- **Region-specific**: AMIs are region-specific. Run the script in each region where you have AMIs

### About ECR Images (aws_resource_cleanup.py)
- The `aws_resource_cleanup.py` script **lists** ECR images only (read-only operation)
- To delete ECR images by ARN, use the `delete_ecr_images.py` or `delete_ecr_images.sh` scripts (see below)

---

## 🗑️ Delete ECR Images by ARN

The `delete_ecr_images.py` (Python) and `delete_ecr_images.sh` (Shell) scripts allow you to delete specific ECR images using their ARNs from a file.

### When to Use This

Use these scripts when you:
- Have a list of specific ECR image ARNs you want to delete
- Need to clean up ECR images across multiple regions
- Want to delete images from different repositories in a single operation
- Have images identified by their full ARN (e.g., from AWS Cost Explorer or compliance reports)

### Setup

1. **Create an input file** with ECR image ARNs (one per line):
   ```bash
   # Copy the example file
   cp images.txt.example images.txt
   
   # Edit with your ARNs
   nano images.txt
   ```

2. **ARN Format**:
   ```
   arn:aws:ecr:<region>:<account-id>:repository/<repo-name>/sha256:<digest>
   ```
   
   Example:
   ```
   arn:aws:ecr:us-east-2:905418167957:repository/myrepo/sha256:abcd1234567890
   ```

### Usage - Python Script

#### Dry Run (Recommended First)
Preview what would be deleted without actually deleting:
```bash
python3 delete_ecr_images.py --file images.txt --profile myprofile --dry-run
```

#### Actual Deletion
Perform the actual deletion:
```bash
python3 delete_ecr_images.py --file images.txt --profile myprofile
```

#### Using Default Profile
```bash
python3 delete_ecr_images.py --file images.txt --profile default
```

### Usage - Shell Script

#### Dry Run (Recommended First)
```bash
./delete_ecr_images.sh --file images.txt --profile myprofile --dry-run
```

#### Actual Deletion
```bash
./delete_ecr_images.sh --file images.txt --profile myprofile
```

#### Help
```bash
./delete_ecr_images.sh --help
```

### Command Line Options (ECR Deletion Scripts)

| Option | Required | Description |
|--------|----------|-------------|
| `--file` | Yes | Path to file containing ECR image ARNs (one per line) |
| `--profile` | Yes | AWS CLI profile name to use for authentication |
| `--dry-run` | No | Preview deletions without performing them (recommended) |
| `--help` | No | Show help message (shell script only) |

### Input File Format

The input file should contain one ARN per line:

```text
# This is a comment - lines starting with # are ignored
arn:aws:ecr:us-east-2:905418167957:repository/myrepo/sha256:abc123...
arn:aws:ecr:us-west-2:905418167957:repository/app-repo/sha256:def456...

# Empty lines are also ignored
arn:aws:ecr:us-east-1:123456789012:repository/test-repo/sha256:789abc...
```

### Features

#### Python Script (`delete_ecr_images.py`)
- ✅ Comprehensive error handling and logging
- ✅ Detailed progress reporting with timestamps
- ✅ AWS credential validation before processing
- ✅ Support for comments and empty lines in input file
- ✅ Automatic region detection from ARNs
- ✅ Colored output for better readability
- ✅ Summary report with success/failure counts
- ✅ Type hints and docstrings for maintainability

#### Shell Script (`delete_ecr_images.sh`)
- ✅ Lightweight, no Python dependencies required
- ✅ Color-coded output for status messages
- ✅ Built-in AWS CLI and profile validation
- ✅ Bash completion-friendly
- ✅ Comprehensive error handling
- ✅ Detailed help documentation
- ✅ Progress tracking and summary

### Example Workflow

1. **Identify images to delete** (e.g., from AWS Console or cost reports)

2. **Create input file** with ARNs:
   ```bash
   cat > images.txt << 'EOF'
   arn:aws:ecr:us-east-2:123456789012:repository/old-app/sha256:abc123...
   arn:aws:ecr:us-east-2:123456789012:repository/old-app/sha256:def456...
   EOF
   ```

3. **Run dry-run** to preview:
   ```bash
   python3 delete_ecr_images.py --file images.txt --profile myprofile --dry-run
   ```

4. **Review output** and verify the images to be deleted

5. **Perform actual deletion**:
   ```bash
   python3 delete_ecr_images.py --file images.txt --profile myprofile
   ```

### Safety Features

1. **Dry Run Mode**: Always test with `--dry-run` first to preview deletions
2. **Profile Validation**: Verifies AWS profile exists and has valid credentials
3. **ARN Validation**: Validates ARN format before attempting deletion
4. **Detailed Logging**: Shows exactly what is being deleted and any errors
5. **Error Resilience**: Continues processing even if individual deletions fail
6. **Summary Report**: Provides counts of successful and failed deletions

---

## 🔧 Troubleshooting

### AWS Credentials Not Found
```
✗ Error: AWS credentials not found. Please configure AWS CLI.
```
**Solution**: Run `aws configure` to set up your credentials

### Permission Denied
```
✗ Error: User is not authorized to perform: ec2:DescribeImages
```
**Solution**: Ensure your IAM user/role has the required permissions (see IAM Permissions section)

### No AMIs Found
```
No AMIs found in this account/region.
```
**Solution**: 
- Verify you're using the correct AWS account ID
- Check if you're in the correct region using `--region` parameter
- Ensure AMIs exist in your account

## 📝 Best Practices

1. **Always test with --dry-run first** before performing live deletions
2. **Backup critical AMIs** by creating snapshots or copying to another region
3. **Tag your AMIs** with meaningful information (environment, version, etc.)
4. **Regular cleanup**: Schedule regular cleanup to avoid accumulating unnecessary AMIs
5. **Monitor costs**: Use AWS Cost Explorer to track EBS snapshot costs
6. **Document retention policies**: Clearly define how many AMIs/images to keep

## 🔄 Automation

You can schedule this script to run automatically using:

### Linux/Mac (cron)
```bash
# Run cleanup every Sunday at 2 AM, keeping 5 most recent AMIs
0 2 * * 0 /usr/bin/python3 /path/to/aws_resource_cleanup.py --aws-account-id 123456789012 --action delete-ami --keep 5
```

### AWS Lambda
Package the script and dependencies as a Lambda function for serverless execution

### AWS Systems Manager
Use Systems Manager Automation to run the script on a schedule

## 📚 Related Documentation

- [AWS ECR Documentation](https://docs.aws.amazon.com/ecr/)
- [AWS AMI Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AMIs.html)
- [Boto3 Documentation](https://boto3.amazonaws.com/v1/documentation/api/latest/index.html)
- [AWS CLI Documentation](https://docs.aws.amazon.com/cli/)

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## 📄 License

This script is part of the AWS-Terraform-Playground project. See the main repository LICENSE file for details.

## ⚡ Future Enhancements

Potential improvements for future versions:

- [ ] Add ECR image deletion functionality
- [ ] Support for deleting associated EBS snapshots
- [ ] Export results to CSV/JSON
- [ ] Support for filtering by tags
- [ ] Multi-region cleanup in a single run
- [ ] Integration with AWS Config for compliance tracking
- [ ] Slack/Email notifications for cleanup operations
- [ ] Cost estimation before deletion
