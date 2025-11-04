#!/bin/bash
#
# ECR Image Deletion Script (Shell Version)
#
# This script deletes ECR (Elastic Container Registry) images based on ARNs 
# provided in a file. It supports AWS CLI profiles and includes a dry-run mode.
#
# Features:
# - Parses ECR image ARNs to extract region, repository, and digest
# - Supports AWS CLI profiles for authentication
# - Dry-run mode to preview deletions without performing them
# - Color-coded output for better readability
# - Input validation and error handling
#
# ARN Format:
#   arn:aws:ecr:<region>:<account-id>:repository/<repo-name>/sha256:<digest>
#
# Usage:
#   # Dry run (preview deletions)
#   ./delete_ecr_images.sh --file images.txt --profile myprofile --dry-run
#
#   # Actual deletion
#   ./delete_ecr_images.sh --file images.txt --profile myprofile
#
# Requirements:
#   - AWS CLI installed and configured
#   - Bash 4.0 or higher
#   - Appropriate ECR permissions (ecr:BatchDeleteImage)
#

set -o pipefail  # Exit on pipe failures

# ============================================================================
# Configuration and Default Values
# ============================================================================

# Default values
PROFILE=""
FILE=""
DRY_RUN=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Counters
SUCCESS_COUNT=0
FAILURE_COUNT=0
TOTAL_COUNT=0

# ============================================================================
# Helper Functions
# ============================================================================

# Print colored messages
print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_dry_run() {
    echo -e "${CYAN}[DRY-RUN]${NC} $1"
}

# Print usage information
usage() {
    cat << EOF
Usage: $0 --file <file> --profile <profile> [--dry-run]

Delete ECR images from a list of ARNs.

Required Arguments:
  --file <file>        Path to file containing ECR image ARNs (one per line)
  --profile <profile>  AWS CLI profile name to use for authentication

Optional Arguments:
  --dry-run           Preview deletions without performing them (recommended)
  --help, -h          Show this help message

Examples:
  # Dry run (preview deletions)
  $0 --file images.txt --profile myprofile --dry-run

  # Actual deletion
  $0 --file images.txt --profile myprofile

ARN Format:
  arn:aws:ecr:<region>:<account-id>:repository/<repo-name>/sha256:<digest>

  Example:
  arn:aws:ecr:us-east-2:111122223333:repository/myrepo/sha256:abcd1234567890

Notes:
  - Lines starting with '#' are treated as comments and ignored
  - Empty lines are ignored
  - The script automatically detects the region from each ARN
  - Requires AWS CLI to be installed and configured
  - Requires appropriate ECR permissions (ecr:BatchDeleteImage)

EOF
    exit 0
}

# Validate that required commands are available
check_dependencies() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed or not in PATH"
        print_info "Please install AWS CLI: https://aws.amazon.com/cli/"
        exit 1
    fi
}

# Validate AWS profile
validate_profile() {
    local profile=$1
    
    # Check if profile exists
    if ! aws configure list-profiles 2>/dev/null | grep -q "^${profile}$"; then
        print_error "AWS profile '${profile}' not found"
        print_info "Available profiles:"
        aws configure list-profiles 2>/dev/null | sed 's/^/  - /'
        exit 1
    fi
    
    # Try to verify credentials
    if ! aws sts get-caller-identity --profile "${profile}" &>/dev/null; then
        print_error "Failed to authenticate with profile '${profile}'"
        print_info "Please check your AWS credentials"
        exit 1
    fi
    
    print_success "AWS profile '${profile}' validated"
}

# Validate input file
validate_file() {
    local file=$1
    
    if [[ ! -f "${file}" ]]; then
        print_error "File not found: ${file}"
        exit 1
    fi
    
    if [[ ! -r "${file}" ]]; then
        print_error "File is not readable: ${file}"
        exit 1
    fi
    
    print_success "Input file '${file}' validated"
}

# Parse ECR image ARN
parse_arn() {
    local arn=$1
    
    # Extract components using sed
    local repo=$(echo "${arn}" | sed -E 's#.+:repository/([^/]+)/sha256:.*#\1#')
    local digest=$(echo "${arn}" | sed -E 's#.+/sha256:(.*)#sha256:\1#')
    local region=$(echo "${arn}" | sed -E 's#arn:aws:ecr:([^:]+):.*#\1#')
    
    # Validate extraction
    if [[ -z "${repo}" || -z "${digest}" || -z "${region}" ]]; then
        return 1
    fi
    
    # Check if extraction was successful by verifying the format
    if [[ "${repo}" == "${arn}" || "${digest}" == "${arn}" || "${region}" == "${arn}" ]]; then
        return 1
    fi
    
    echo "${region}|${repo}|${digest}"
    return 0
}

# Delete ECR image
delete_image() {
    local repo=$1
    local digest=$2
    local region=$3
    local profile=$4
    local dry_run=$5
    
    if ${dry_run}; then
        print_dry_run "Would delete image from repository '${repo}' in region '${region}' with digest '${digest}'"
        return 0
    else
        print_info "Deleting image from repository '${repo}' in region '${region}' with digest '${digest}'..."
        
        # Perform the deletion
        local output
        if output=$(aws ecr batch-delete-image \
            --repository-name "${repo}" \
            --image-ids "imageDigest=${digest}" \
            --region "${region}" \
            --profile "${profile}" 2>&1); then
            
            # Check for failures in the response
            if echo "${output}" | grep -q '"failures": \[\]' || ! echo "${output}" | grep -q '"failures"'; then
                print_success "Image deleted successfully"
                return 0
            else
                print_error "Deletion completed with failures"
                echo "${output}" | grep -A5 '"failures"' >&2
                return 1
            fi
        else
            print_error "Failed to delete image"
            echo "${output}" >&2
            return 1
        fi
    fi
}

# ============================================================================
# Main Script
# ============================================================================

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --file)
            FILE="$2"
            shift 2
            ;;
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            echo ""
            usage
            ;;
    esac
done

# Check for required arguments
if [[ -z "${FILE}" ]]; then
    print_error "Missing required argument: --file"
    echo ""
    usage
fi

if [[ -z "${PROFILE}" ]]; then
    print_error "Missing required argument: --profile"
    echo ""
    usage
fi

# Print header
echo "================================================================================"
echo "ECR Image Deletion Script"
echo "================================================================================"
if ${DRY_RUN}; then
    echo -e "Mode: ${CYAN}DRY-RUN (no deletions will be performed)${NC}"
else
    echo -e "Mode: ${RED}LIVE (images will be deleted)${NC}"
fi
echo "Profile: ${PROFILE}"
echo "Input file: ${FILE}"
echo "================================================================================"
echo ""

# Validate dependencies and inputs
check_dependencies
validate_profile "${PROFILE}"
validate_file "${FILE}"

echo ""
print_info "Processing ARNs from file..."
echo ""

# Process each line in the file
while IFS= read -r line || [[ -n "${line}" ]]; do
    # Skip empty lines and comments
    if [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    ((TOTAL_COUNT++))
    
    echo "--------------------------------------------------------------------------------"
    echo "[${TOTAL_COUNT}] Processing ARN: ${line}"
    
    # Parse the ARN
    if parsed=$(parse_arn "${line}"); then
        IFS='|' read -r region repo digest <<< "${parsed}"
        
        # Delete the image
        if delete_image "${repo}" "${digest}" "${region}" "${PROFILE}" ${DRY_RUN}; then
            ((SUCCESS_COUNT++))
        else
            ((FAILURE_COUNT++))
        fi
    else
        print_error "Invalid ARN format: ${line}"
        print_info "Expected format: arn:aws:ecr:<region>:<account-id>:repository/<repo>/sha256:<digest>"
        ((FAILURE_COUNT++))
    fi
    
    echo ""
    
done < "${FILE}"

# Print summary
echo "================================================================================"
echo "Summary"
echo "================================================================================"
print_info "Total ARNs processed: ${TOTAL_COUNT}"

if ${DRY_RUN}; then
    print_info "Would delete: ${SUCCESS_COUNT} image(s)"
    if [[ ${FAILURE_COUNT} -gt 0 ]]; then
        print_warning "Would fail: ${FAILURE_COUNT} image(s)"
    fi
    echo ""
    print_info "Run without --dry-run to perform actual deletions"
else
    print_success "Successfully deleted: ${SUCCESS_COUNT} image(s)"
    if [[ ${FAILURE_COUNT} -gt 0 ]]; then
        print_warning "Failed to delete: ${FAILURE_COUNT} image(s)"
    fi
fi
echo "================================================================================"

# Exit with appropriate code
if [[ ${FAILURE_COUNT} -gt 0 ]]; then
    exit 1
else
    exit 0
fi
