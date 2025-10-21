#!/bin/bash
# Example usage script for AWS Resource Cleanup
# This script demonstrates various ways to use the aws_resource_cleanup.py script

# Set your AWS Account ID
AWS_ACCOUNT_ID="123456789012"  # Replace with your actual AWS Account ID

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "========================================================================"
echo "AWS Resource Cleanup - Example Usage"
echo "========================================================================"
echo ""
echo -e "${YELLOW}Note: This is an example script. Update AWS_ACCOUNT_ID before running.${NC}"
echo ""

# Example 1: List ECR Images
echo -e "${GREEN}Example 1: List all ECR images${NC}"
echo "Command: python aws_resource_cleanup.py --aws-account-id $AWS_ACCOUNT_ID --action list-ecr"
echo ""

# Uncomment to run
# python aws_resource_cleanup.py --aws-account-id $AWS_ACCOUNT_ID --action list-ecr

# Example 2: List AMIs
echo -e "${GREEN}Example 2: List all AMIs${NC}"
echo "Command: python aws_resource_cleanup.py --aws-account-id $AWS_ACCOUNT_ID --action list-ami"
echo ""

# Uncomment to run
# python aws_resource_cleanup.py --aws-account-id $AWS_ACCOUNT_ID --action list-ami

# Example 3: Delete AMIs (Dry Run)
echo -e "${GREEN}Example 3: Delete old AMIs (DRY RUN - keeps 5 most recent)${NC}"
echo "Command: python aws_resource_cleanup.py --aws-account-id $AWS_ACCOUNT_ID --action delete-ami --keep 5 --dry-run"
echo ""

# Uncomment to run
# python aws_resource_cleanup.py --aws-account-id $AWS_ACCOUNT_ID --action delete-ami --keep 5 --dry-run

# Example 4: Delete AMIs with different retention (Dry Run)
echo -e "${GREEN}Example 4: Delete old AMIs keeping only 10 (DRY RUN)${NC}"
echo "Command: python aws_resource_cleanup.py --aws-account-id $AWS_ACCOUNT_ID --action delete-ami --keep 10 --dry-run"
echo ""

# Uncomment to run
# python aws_resource_cleanup.py --aws-account-id $AWS_ACCOUNT_ID --action delete-ami --keep 10 --dry-run

# Example 5: List AMIs in a specific region
echo -e "${GREEN}Example 5: List AMIs in us-west-2 region${NC}"
echo "Command: python aws_resource_cleanup.py --aws-account-id $AWS_ACCOUNT_ID --region us-west-2 --action list-ami"
echo ""

# Uncomment to run
# python aws_resource_cleanup.py --aws-account-id $AWS_ACCOUNT_ID --region us-west-2 --action list-ami

echo "========================================================================"
echo -e "${RED}IMPORTANT: For scenario with 400 AMIs, keeping 5, deleting 395:${NC}"
echo "========================================================================"
echo ""
echo "Step 1: First, run a dry-run to see what would be deleted:"
echo "  python aws_resource_cleanup.py --aws-account-id $AWS_ACCOUNT_ID --action delete-ami --keep 5 --dry-run"
echo ""
echo "Step 2: After reviewing, run the actual deletion:"
echo "  python aws_resource_cleanup.py --aws-account-id $AWS_ACCOUNT_ID --action delete-ami --keep 5"
echo ""
echo -e "${YELLOW}Warning: The actual deletion will require typing 'yes' to confirm!${NC}"
echo ""
