#!/usr/bin/env python3
"""
AWS Resource Cleanup Script

This script helps manage AWS resources by:
1. Listing ECR images with their last used dates
2. Listing AMIs with their metadata and last used dates
3. Deleting old AMIs while keeping a specified number of recent images

Usage:
    python aws_resource_cleanup.py --aws-account-id <account-id> --action list-ecr
    python aws_resource_cleanup.py --aws-account-id <account-id> --action list-ami
    python aws_resource_cleanup.py --aws-account-id <account-id> --action delete-ami --keep 5
"""

import argparse
import boto3
import sys
from datetime import datetime
from typing import List, Dict
from botocore.exceptions import ClientError, NoCredentialsError


class AWSResourceManager:
    """Manages AWS ECR and AMI resources"""
    
    def __init__(self, aws_account_id: str, region: str = None):
        """
        Initialize AWS Resource Manager
        
        Args:
            aws_account_id: AWS Account ID
            region: AWS region (defaults to current configured region)
        """
        self.aws_account_id = aws_account_id
        self.region = region or boto3.Session().region_name
        
        try:
            self.ecr_client = boto3.client('ecr', region_name=self.region)
            self.ec2_client = boto3.client('ec2', region_name=self.region)
            print(f"✓ Connected to AWS Account: {self.aws_account_id}")
            print(f"✓ Using Region: {self.region}")
        except NoCredentialsError:
            print("✗ Error: AWS credentials not found. Please configure AWS CLI.")
            sys.exit(1)
        except Exception as e:
            print(f"✗ Error initializing AWS clients: {str(e)}")
            sys.exit(1)
    
    def list_ecr_images(self) -> List[Dict]:
        """
        List all ECR images with their metadata
        
        Returns:
            List of dictionaries containing ECR image information
        """
        print("\n" + "="*80)
        print("ECR IMAGES REPORT")
        print("="*80)
        
        all_images = []
        
        try:
            # Get all repositories
            repositories = self.ecr_client.describe_repositories()
            
            if not repositories['repositories']:
                print("No ECR repositories found in this account/region.")
                return all_images
            
            for repo in repositories['repositories']:
                repo_name = repo['repositoryName']
                repo_uri = repo['repositoryUri']
                
                print(f"\n📦 Repository: {repo_name}")
                print(f"   URI: {repo_uri}")
                
                # Get images in this repository
                try:
                    images_response = self.ecr_client.describe_images(
                        repositoryName=repo_name
                    )
                    
                    images = images_response.get('imageDetails', [])
                    
                    # Sort by pushed date (most recent first)
                    images.sort(key=lambda x: x.get('imagePushedAt', datetime.min), reverse=True)
                    
                    print(f"   Total Images: {len(images)}")
                    
                    for idx, image in enumerate(images, 1):
                        image_tags = image.get('imageTags', ['<untagged>'])
                        pushed_at = image.get('imagePushedAt', 'Unknown')
                        size_mb = image.get('imageSizeInBytes', 0) / (1024 * 1024)
                        digest = image.get('imageDigest', 'Unknown')
                        
                        image_info = {
                            'repository': repo_name,
                            'uri': repo_uri,
                            'tags': image_tags,
                            'pushed_at': pushed_at,
                            'size_mb': size_mb,
                            'digest': digest
                        }
                        all_images.append(image_info)
                        
                        print(f"   {idx}. Tags: {', '.join(image_tags)}")
                        print(f"      Pushed: {pushed_at}")
                        print(f"      Size: {size_mb:.2f} MB")
                        print(f"      Digest: {digest[:20]}...")
                
                except ClientError as e:
                    print(f"   ✗ Error listing images: {e}")
                    
        except ClientError as e:
            print(f"✗ Error listing repositories: {e}")
        
        print(f"\n📊 Total ECR images across all repositories: {len(all_images)}")
        return all_images
    
    def list_amis(self) -> List[Dict]:
        """
        List all AMIs owned by the account with their metadata
        
        Returns:
            List of dictionaries containing AMI information
        """
        print("\n" + "="*80)
        print("AMI (Amazon Machine Images) REPORT")
        print("="*80)
        
        all_amis = []
        
        try:
            # Get AMIs owned by this account
            response = self.ec2_client.describe_images(
                Owners=[self.aws_account_id]
            )
            
            amis = response.get('Images', [])
            
            if not amis:
                print("No AMIs found in this account/region.")
                return all_amis
            
            # Sort by creation date (most recent first)
            amis.sort(key=lambda x: x.get('CreationDate', ''), reverse=True)
            
            print(f"\nTotal AMIs: {len(amis)}")
            print("-" * 80)
            
            for idx, ami in enumerate(amis, 1):
                ami_id = ami.get('ImageId', 'Unknown')
                ami_name = ami.get('Name', '<no name>')
                creation_date = ami.get('CreationDate', 'Unknown')
                state = ami.get('State', 'Unknown')
                description = ami.get('Description', '<no description>')
                architecture = ami.get('Architecture', 'Unknown')
                
                # Get tags
                tags = ami.get('Tags', [])
                tag_dict = {tag['Key']: tag['Value'] for tag in tags}
                
                ami_info = {
                    'ami_id': ami_id,
                    'name': ami_name,
                    'creation_date': creation_date,
                    'state': state,
                    'description': description,
                    'architecture': architecture,
                    'tags': tag_dict
                }
                all_amis.append(ami_info)
                
                print(f"\n{idx}. AMI ID: {ami_id}")
                print(f"   Name: {ami_name}")
                print(f"   Created: {creation_date}")
                print(f"   State: {state}")
                print(f"   Architecture: {architecture}")
                if description and description != '<no description>':
                    print(f"   Description: {description[:60]}...")
                if tag_dict:
                    print(f"   Tags: {tag_dict}")
            
        except ClientError as e:
            print(f"✗ Error listing AMIs: {e}")
        
        print(f"\n📊 Total AMIs: {len(all_amis)}")
        return all_amis
    
    def delete_old_amis(self, keep_count: int = 5, dry_run: bool = True) -> int:
        """
        Delete old AMIs, keeping only the specified number of most recent ones
        
        Args:
            keep_count: Number of most recent AMIs to keep
            dry_run: If True, only simulate deletion without actually deleting
            
        Returns:
            Number of AMIs deleted (or would be deleted in dry-run mode)
        """
        print("\n" + "="*80)
        print(f"AMI DELETION {'(DRY RUN)' if dry_run else '(LIVE)'}")
        print("="*80)
        
        amis = self.list_amis()
        
        if len(amis) <= keep_count:
            print(f"\n✓ Only {len(amis)} AMI(s) found. Keeping all as requested count is {keep_count}.")
            return 0
        
        # Calculate how many to delete
        amis_to_delete = amis[keep_count:]
        delete_count = len(amis_to_delete)
        
        print(f"\n📋 Analysis:")
        print(f"   Total AMIs: {len(amis)}")
        print(f"   AMIs to keep: {keep_count}")
        print(f"   AMIs to delete: {delete_count}")
        
        if dry_run:
            print(f"\n⚠️  DRY RUN MODE - No AMIs will be deleted")
        else:
            print(f"\n⚠️  WARNING: This will DELETE {delete_count} AMIs!")
        
        print("\n" + "-"*80)
        print("AMIs TO KEEP (most recent):")
        print("-"*80)
        for idx, ami in enumerate(amis[:keep_count], 1):
            print(f"{idx}. {ami['ami_id']} - {ami['name']} (Created: {ami['creation_date']})")
        
        print("\n" + "-"*80)
        print(f"AMIs TO DELETE (older):")
        print("-"*80)
        for idx, ami in enumerate(amis_to_delete, 1):
            print(f"{idx}. {ami['ami_id']} - {ami['name']} (Created: {ami['creation_date']})")
        
        if not dry_run:
            # Ask for confirmation
            print("\n" + "="*80)
            confirmation = input(f"⚠️  Type 'yes' to confirm deletion of {delete_count} AMIs: ")
            
            if confirmation.lower() != 'yes':
                print("❌ Deletion cancelled by user.")
                return 0
            
            # Proceed with deletion
            deleted_count = 0
            failed_count = 0
            
            print("\n🗑️  Deleting AMIs...")
            for ami in amis_to_delete:
                ami_id = ami['ami_id']
                try:
                    # First, deregister the AMI
                    print(f"   Deregistering {ami_id}...", end=" ")
                    self.ec2_client.deregister_image(ImageId=ami_id)
                    
                    # Note: Snapshots associated with the AMI are NOT automatically deleted
                    # You may want to delete them separately if needed
                    
                    print("✓ Success")
                    deleted_count += 1
                    
                except ClientError as e:
                    print(f"✗ Failed: {e}")
                    failed_count += 1
            
            print(f"\n📊 Deletion Summary:")
            print(f"   Successfully deleted: {deleted_count}")
            print(f"   Failed: {failed_count}")
            
            return deleted_count
        else:
            print(f"\n✓ Dry run complete. {delete_count} AMI(s) would be deleted in live mode.")
            return delete_count


def main():
    """Main entry point for the script"""
    parser = argparse.ArgumentParser(
        description='AWS ECR and AMI Resource Management Script',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  # List all ECR images
  python aws_resource_cleanup.py --aws-account-id 123456789012 --action list-ecr
  
  # List all AMIs
  python aws_resource_cleanup.py --aws-account-id 123456789012 --action list-ami
  
  # Delete old AMIs (dry run - keeps 5 most recent)
  python aws_resource_cleanup.py --aws-account-id 123456789012 --action delete-ami --keep 5 --dry-run
  
  # Delete old AMIs (live - keeps 5 most recent)
  python aws_resource_cleanup.py --aws-account-id 123456789012 --action delete-ami --keep 5
  
  # Specify a different region
  python aws_resource_cleanup.py --aws-account-id 123456789012 --region us-west-2 --action list-ami
        '''
    )
    
    parser.add_argument(
        '--aws-account-id',
        required=True,
        help='AWS Account ID'
    )
    
    parser.add_argument(
        '--region',
        default=None,
        help='AWS Region (defaults to configured region)'
    )
    
    parser.add_argument(
        '--action',
        required=True,
        choices=['list-ecr', 'list-ami', 'delete-ami'],
        help='Action to perform'
    )
    
    parser.add_argument(
        '--keep',
        type=int,
        default=5,
        help='Number of most recent AMIs to keep when deleting (default: 5)'
    )
    
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Perform a dry run (simulate deletion without actually deleting)'
    )
    
    args = parser.parse_args()
    
    # Validate keep count
    if args.action == 'delete-ami' and args.keep < 0:
        print("Error: --keep must be a positive number")
        sys.exit(1)
    
    # Initialize resource manager
    manager = AWSResourceManager(args.aws_account_id, args.region)
    
    # Execute requested action
    if args.action == 'list-ecr':
        manager.list_ecr_images()
    
    elif args.action == 'list-ami':
        manager.list_amis()
    
    elif args.action == 'delete-ami':
        # Default to dry-run if not explicitly set to live mode
        dry_run = args.dry_run if '--dry-run' in sys.argv or '--keep' in sys.argv else True
        
        # If user didn't specify --dry-run, ask for confirmation
        if not args.dry_run and '--dry-run' not in sys.argv:
            print("\n⚠️  WARNING: You are about to perform a LIVE deletion!")
            print("   Use --dry-run flag to test without deleting.")
            response = input("   Continue with LIVE deletion? (yes/no): ")
            if response.lower() != 'yes':
                print("Operation cancelled.")
                sys.exit(0)
            dry_run = False
        
        manager.delete_old_amis(keep_count=args.keep, dry_run=dry_run)
    
    print("\n✓ Script completed successfully!")


if __name__ == '__main__':
    main()
