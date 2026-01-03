#!/bin/bash
# GitOps Exception Management Pipeline
# This script is meant to run in CI/CD to check for expired exceptions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "========================================="
echo "AMI Policy Exception Check"
echo "========================================="
echo ""

# Check if Python script exists
if [ ! -f "$SCRIPT_DIR/exception_manager.py" ]; then
    echo -e "${RED}Error: exception_manager.py not found${NC}"
    exit 1
fi

# Check for expired exceptions
echo "Checking for expired exceptions..."
python3 "$SCRIPT_DIR/exception_manager.py" --check --days 7

EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}⚠️  EXPIRED EXCEPTIONS FOUND${NC}"
    echo -e "${RED}=========================================${NC}"
    echo ""
    echo "Action Required:"
    echo "1. Review the expired exception accounts listed above"
    echo "2. Update terraform-module/variables.tf to remove expired entries"
    echo "3. Run terraform plan to verify changes"
    echo "4. Submit PR for review"
    echo ""
    echo "Example:"
    echo "  cd terraform-module"
    echo "  vim variables.tf  # Remove expired accounts from exception_accounts"
    echo "  terraform plan"
    echo ""
    exit 1
else
    echo ""
    echo -e "${GREEN}✅ No expired exceptions found${NC}"
    exit 0
fi
