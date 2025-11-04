#!/usr/bin/env python3
"""
ECR Image Deletion Script

This script deletes ECR (Elastic Container Registry) images based on ARNs provided in a file.
It supports AWS CLI profiles and includes a dry-run mode for safe testing.

Features:
- Parses ECR image ARNs to extract region, repository, and digest
- Supports AWS CLI profiles for authentication
- Dry-run mode to preview deletions without performing them
- Comprehensive error handling and logging
- Multi-region support (automatically detects region from ARN)

ARN Format:
    arn:aws:ecr:<region>:<account-id>:repository/<repo-name>/sha256:<digest>

Usage:
    # Dry run (preview deletions)
    python3 delete_ecr_images.py --file images.txt --profile myprofile --dry-run
    
    # Actual deletion
    python3 delete_ecr_images.py --file images.txt --profile myprofile
"""

import argparse
import boto3
import re
import sys
import logging
from typing import Tuple, Optional
from botocore.exceptions import ClientError, NoCredentialsError, ProfileNotFound


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


def parse_arn(arn: str) -> Tuple[str, str, str]:
    """
    Extract region, repository name, and digest from ECR image ARN.
    
    Args:
        arn: ECR image ARN in the format:
             arn:aws:ecr:<region>:<account-id>:repository/<repo-name>/sha256:<digest>
    
    Returns:
        Tuple of (region, repository_name, digest)
    
    Raises:
        ValueError: If ARN format is invalid
    
    Example:
        >>> parse_arn("arn:aws:ecr:us-east-2:111122223333:repository/myrepo/sha256:abcd1234")
        ('us-east-2', 'myrepo', 'sha256:abcd1234')
    """
    # Pattern to match ECR image ARN format
    pattern = r"arn:aws:ecr:(?P<region>[^:]+):\d+:repository/(?P<repo>[^/]+)/sha256:(?P<digest>[a-f0-9]+)"
    match = re.match(pattern, arn.strip())
    
    if not match:
        raise ValueError(f"Invalid ECR image ARN format: {arn}")
    
    region = match.group("region")
    repository = match.group("repo")
    digest = f"sha256:{match.group('digest')}"
    
    return region, repository, digest


def load_arns_from_file(file_path: str) -> list:
    """
    Load and validate ARNs from a file.
    
    Args:
        file_path: Path to file containing ECR image ARNs (one per line)
    
    Returns:
        List of non-empty, stripped ARN strings
    
    Raises:
        FileNotFoundError: If the file doesn't exist
        IOError: If there's an error reading the file
    """
    try:
        with open(file_path, "r") as f:
            lines = [line.strip() for line in f if line.strip() and not line.strip().startswith("#")]
        
        if not lines:
            logger.warning(f"No ARNs found in file: {file_path}")
        else:
            logger.info(f"Loaded {len(lines)} ARN(s) from {file_path}")
        
        return lines
    
    except FileNotFoundError:
        logger.error(f"File not found: {file_path}")
        raise
    except IOError as e:
        logger.error(f"Error reading file {file_path}: {e}")
        raise


def delete_ecr_image(
    session: boto3.Session,
    region: str,
    repository: str,
    digest: str,
    dry_run: bool = False
) -> bool:
    """
    Delete an ECR image by its digest.
    
    Args:
        session: Boto3 session with AWS credentials
        region: AWS region where the repository exists
        repository: Name of the ECR repository
        digest: Image digest (e.g., 'sha256:abcd1234...')
        dry_run: If True, only simulate the deletion
    
    Returns:
        True if deletion was successful (or would be in dry-run), False otherwise
    """
    try:
        ecr_client = session.client("ecr", region_name=region)
        
        if dry_run:
            logger.info(
                f"[DRY-RUN] Would delete image from repository '{repository}' "
                f"in region '{region}' with digest '{digest}'"
            )
            return True
        
        logger.info(
            f"Deleting image from repository '{repository}' "
            f"in region '{region}' with digest '{digest}'..."
        )
        
        response = ecr_client.batch_delete_image(
            repositoryName=repository,
            imageIds=[{"imageDigest": digest}]
        )
        
        # Check for failures in the response
        failures = response.get("failures", [])
        if failures:
            for failure in failures:
                logger.error(
                    f"Failed to delete image: {failure.get('failureReason', 'Unknown reason')}"
                )
            return False
        
        # Check if images were actually deleted
        deleted_images = response.get("imageIds", [])
        if deleted_images:
            logger.info(f"✅ Successfully deleted image with digest: {digest}")
            return True
        else:
            logger.warning(f"No image was deleted for digest: {digest}")
            return False
    
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        
        if error_code == 'RepositoryNotFoundException':
            logger.error(f"Repository '{repository}' not found in region '{region}'")
        elif error_code == 'ImageNotFoundException':
            logger.error(f"Image with digest '{digest}' not found in repository '{repository}'")
        else:
            logger.error(f"AWS Error ({error_code}): {error_message}")
        
        return False
    
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return False


def main():
    """Main entry point for the script"""
    parser = argparse.ArgumentParser(
        description="Delete ECR images from a list of ARNs",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Dry run (preview deletions without performing them)
  python3 delete_ecr_images.py --file images.txt --profile myprofile --dry-run
  
  # Actual deletion
  python3 delete_ecr_images.py --file images.txt --profile myprofile
  
  # Using default AWS profile
  python3 delete_ecr_images.py --file images.txt --profile default

ARN Format:
  arn:aws:ecr:<region>:<account-id>:repository/<repo-name>/sha256:<digest>
  
  Example:
  arn:aws:ecr:us-east-2:111122223333:repository/myrepo/sha256:abcd1234567890

Notes:
  - Lines starting with '#' in the input file are treated as comments
  - Empty lines are ignored
  - The script automatically detects the region from each ARN
  - Requires appropriate ECR permissions (ecr:BatchDeleteImage)
        """
    )
    
    parser.add_argument(
        "--file",
        required=True,
        help="Path to file containing ECR image ARNs (one per line)"
    )
    
    parser.add_argument(
        "--profile",
        required=True,
        help="AWS CLI profile name to use for authentication"
    )
    
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview deletions without performing them (recommended for first run)"
    )
    
    args = parser.parse_args()
    
    # Print header
    print("=" * 80)
    print("ECR Image Deletion Script")
    print("=" * 80)
    print(f"Mode: {'DRY-RUN (no deletions will be performed)' if args.dry_run else 'LIVE (images will be deleted)'}")
    print(f"Profile: {args.profile}")
    print(f"Input file: {args.file}")
    print("=" * 80)
    print()
    
    # Load AWS session with the given profile
    try:
        session = boto3.Session(profile_name=args.profile)
        # Verify credentials by getting caller identity
        sts = session.client('sts')
        identity = sts.get_caller_identity()
        logger.info(f"✅ AWS profile '{args.profile}' loaded successfully")
        logger.info(f"   Account: {identity.get('Account')}")
        logger.info(f"   User/Role: {identity.get('Arn')}")
    except ProfileNotFound:
        logger.error(f"❌ AWS profile '{args.profile}' not found")
        logger.error("   Available profiles can be listed with: aws configure list-profiles")
        sys.exit(1)
    except NoCredentialsError:
        logger.error("❌ No AWS credentials found")
        logger.error("   Please configure AWS CLI: aws configure")
        sys.exit(1)
    except Exception as e:
        logger.error(f"❌ Failed to load AWS profile '{args.profile}': {e}")
        sys.exit(1)
    
    # Load ARNs from file
    try:
        arns = load_arns_from_file(args.file)
    except (FileNotFoundError, IOError):
        sys.exit(1)
    
    if not arns:
        logger.warning("No ARNs to process. Exiting.")
        sys.exit(0)
    
    # Process each ARN
    print()
    logger.info(f"Processing {len(arns)} ARN(s)...")
    print()
    
    success_count = 0
    failure_count = 0
    
    for idx, arn in enumerate(arns, 1):
        print(f"[{idx}/{len(arns)}] Processing ARN: {arn}")
        
        try:
            # Parse the ARN
            region, repository, digest = parse_arn(arn)
            
            # Delete the image
            if delete_ecr_image(session, region, repository, digest, args.dry_run):
                success_count += 1
            else:
                failure_count += 1
        
        except ValueError as e:
            logger.error(f"❌ {e}")
            failure_count += 1
        
        except Exception as e:
            logger.error(f"❌ Unexpected error processing ARN '{arn}': {e}")
            failure_count += 1
        
        print()  # Add blank line between entries
    
    # Print summary
    print("=" * 80)
    print("Summary")
    print("=" * 80)
    if args.dry_run:
        logger.info(f"Would delete: {success_count} image(s)")
        logger.info(f"Would fail: {failure_count} image(s)")
        logger.info("Run without --dry-run to perform actual deletions")
    else:
        logger.info(f"Successfully deleted: {success_count} image(s)")
        if failure_count > 0:
            logger.warning(f"Failed to delete: {failure_count} image(s)")
    print("=" * 80)
    
    # Exit with appropriate code
    sys.exit(0 if failure_count == 0 else 1)


if __name__ == "__main__":
    main()
