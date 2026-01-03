#!/usr/bin/env python3
"""
AMI Governance Policy Generator

Reads config/ami_publishers.json and generates:
1. dist/declarative-policy-ec2.json (AWS Organizations declarative policy)
2. dist/scp-ami-guardrail.json (Service Control Policy)

Both policies enforce the same AMI allowlist with active (non-expired) accounts.

Usage:
    python generate_policies.py [--mode audit|enabled]
    
    --mode: Sets allowed_images_settings enforcement mode
            - audit: Log violations but don't block (default)
            - enabled: Block non-compliant EC2 launches
"""

import json
import argparse
from datetime import datetime, date
from pathlib import Path
from typing import Dict, List, Set


class AMIPolicyGenerator:
    """Generate AWS Organizations policies for AMI governance."""
    
    def __init__(self, config_path: str = "config/ami_publishers.json"):
        """Initialize generator with config file."""
        self.config_path = Path(config_path)
        self.config = self._load_config()
        self.generation_timestamp = datetime.utcnow().isoformat() + "Z"
        
    def _load_config(self) -> dict:
        """Load and validate configuration file."""
        if not self.config_path.exists():
            raise FileNotFoundError(f"Config file not found: {self.config_path}")
        
        with open(self.config_path, 'r') as f:
            config = json.load(f)
        
        # Validate required fields
        required_fields = ['ops_publisher_account', 'vendor_publisher_accounts', 
                          'exception_accounts', 'policy_config']
        for field in required_fields:
            if field not in config:
                raise ValueError(f"Missing required field in config: {field}")
        
        return config
    
    def _get_active_allowlist(self) -> Set[str]:
        """
        Build allowlist of approved AMI publisher accounts.
        
        Returns:
            Set of account IDs that are currently approved (including non-expired exceptions)
        """
        allowlist = set()
        
        # Add ops publisher
        ops_account = self.config['ops_publisher_account']['account_id']
        allowlist.add(ops_account)
        
        # Add vendor publishers
        for vendor in self.config['vendor_publisher_accounts']:
            allowlist.add(vendor['account_id'])
        
        # Add non-expired exceptions
        today = date.today().isoformat()
        for exception in self.config['exception_accounts']:
            expires_on = exception.get('expires_on')
            if not expires_on:
                raise ValueError(f"Exception account {exception['account_id']} missing expires_on")
            
            if expires_on >= today:
                allowlist.add(exception['account_id'])
                print(f"✓ Active exception: {exception['account_id']} "
                      f"(expires {expires_on}) - {exception['reason']}")
            else:
                print(f"✗ Expired exception: {exception['account_id']} "
                      f"(expired {expires_on}) - EXCLUDED from allowlist")
        
        return allowlist
    
    def generate_declarative_policy(self, enforcement_mode: str = "audit_mode") -> dict:
        """
        Generate AWS Organizations declarative policy for EC2.
        
        Args:
            enforcement_mode: "audit_mode" or "enabled"
        
        Returns:
            Declarative policy JSON structure
        """
        allowlist = self._get_active_allowlist()
        
        policy = {
            "policy_description": "AMI Governance - Restrict EC2 launches to approved AMI publishers only",
            "policy_name": "ami-governance-declarative-policy",
            "policy_type": "DECLARATIVE_POLICY_EC2",
            "generated_at": self.generation_timestamp,
            "generated_by": "generate_policies.py",
            "source_config": str(self.config_path),
            "active_allowlist_count": len(allowlist),
            
            "content": {
                "ec2": {
                    "@@operators_allowed_for_child_policies": ["@@none"],
                    
                    "ec2_attributes": {
                        "image_block_public_access": {
                            "@@operators_allowed_for_child_policies": ["@@none"],
                            "state": "block_new_sharing"
                        },
                        
                        "allowed_images_settings": {
                            "@@operators_allowed_for_child_policies": ["@@none"],
                            
                            "state": enforcement_mode,
                            
                            "image_criteria": {
                                "criteria_1": {
                                    "allowed_image_providers": sorted(list(allowlist))
                                }
                            },
                            
                            "exception_message": (
                                "AMI not approved for use in this organization. "
                                "Only images from approved publisher accounts are permitted. "
                                "To request an exception, submit a ticket at: "
                                f"{self.config['policy_config'].get('exception_request_url', 'https://jira.company.com')} "
                                "with business justification, duration needed (max 90 days), and security approval. "
                                "See docs/runbook-ami-governance.md for the exception process."
                            )
                        }
                    }
                }
            }
        }
        
        return policy
    
    def generate_scp_policy(self) -> dict:
        """
        Generate Service Control Policy for AMI guardrails.
        
        Returns:
            SCP policy JSON structure
        """
        allowlist = self._get_active_allowlist()
        
        # Build the condition for allowed AMI owners
        owner_condition = {
            "StringNotEquals": {
                "ec2:Owner": sorted(list(allowlist))
            }
        }
        
        policy = {
            "policy_description": "AMI Governance SCP - Deny EC2 launches with non-approved AMIs and prevent AMI creation/sideload",
            "policy_name": "scp-ami-guardrail",
            "policy_type": "SERVICE_CONTROL_POLICY",
            "generated_at": self.generation_timestamp,
            "generated_by": "generate_policies.py",
            "source_config": str(self.config_path),
            "active_allowlist_count": len(allowlist),
            
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "DenyEC2LaunchWithNonApprovedAMIs",
                    "Effect": "Deny",
                    "Action": [
                        "ec2:RunInstances",
                        "ec2:CreateFleet",
                        "ec2:RequestSpotInstances",
                        "ec2:RunScheduledInstances"
                    ],
                    "Resource": "arn:aws:ec2:*::image/*",
                    "Condition": owner_condition
                },
                {
                    "Sid": "DenyAMICreationAndSideload",
                    "Effect": "Deny",
                    "Action": [
                        "ec2:CreateImage",
                        "ec2:CopyImage",
                        "ec2:RegisterImage",
                        "ec2:ImportImage"
                    ],
                    "Resource": "*",
                    "Condition": {
                        "StringNotEquals": {
                            "aws:PrincipalOrgID": "o-placeholder"
                        }
                    }
                },
                {
                    "Sid": "DenyPublicAMISharing",
                    "Effect": "Deny",
                    "Action": [
                        "ec2:ModifyImageAttribute"
                    ],
                    "Resource": "arn:aws:ec2:*::image/*",
                    "Condition": {
                        "StringEquals": {
                            "ec2:Add/group": "all"
                        }
                    }
                }
            ]
        }
        
        return policy
    
    def write_policy(self, policy: dict, output_path: str) -> None:
        """Write policy to file with proper formatting."""
        output_file = Path(output_path)
        output_file.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_file, 'w') as f:
            json.dump(policy, f, indent=2)
        
        print(f"✓ Generated: {output_file}")
    
    def generate_all(self, enforcement_mode: str = "audit_mode") -> None:
        """Generate all policy files."""
        print("\n" + "="*70)
        print("AMI GOVERNANCE POLICY GENERATOR")
        print("="*70)
        print(f"Config: {self.config_path}")
        print(f"Enforcement Mode: {enforcement_mode}")
        print(f"Generated: {self.generation_timestamp}")
        print("="*70 + "\n")
        
        print("Building active allowlist...")
        allowlist = self._get_active_allowlist()
        
        print(f"\n{'='*70}")
        print(f"ACTIVE ALLOWLIST SUMMARY")
        print(f"{'='*70}")
        print(f"Total approved accounts: {len(allowlist)}")
        print(f"Accounts: {', '.join(sorted(allowlist))}")
        print(f"{'='*70}\n")
        
        # Generate declarative policy
        print("Generating declarative policy...")
        declarative_policy = self.generate_declarative_policy(enforcement_mode)
        self.write_policy(declarative_policy, "dist/declarative-policy-ec2.json")
        
        # Generate SCP
        print("\nGenerating SCP...")
        scp_policy = self.generate_scp_policy()
        self.write_policy(scp_policy, "dist/scp-ami-guardrail.json")
        
        # Verify consistency
        self._verify_consistency(declarative_policy, scp_policy)
        
        print(f"\n{'='*70}")
        print("✓ Policy generation complete!")
        print("="*70)
        print("\nNext steps:")
        print("1. Review generated policies in dist/")
        print("2. Apply declarative-policy-ec2.json at AWS Organizations Root")
        print("3. Apply scp-ami-guardrail.json to workload OUs")
        print("4. See docs/runbook-ami-governance.md for detailed instructions")
        print("="*70 + "\n")
    
    def _verify_consistency(self, declarative_policy: dict, scp_policy: dict) -> None:
        """Verify both policies use the same allowlist."""
        print("\nVerifying policy consistency...")
        
        # Extract allowlists
        dec_allowlist = set(
            declarative_policy['content']['ec2']['ec2_attributes']
            ['allowed_images_settings']['image_criteria']['criteria_1']
            ['allowed_image_providers']
        )
        
        scp_allowlist = set(
            scp_policy['Statement'][0]['Condition']['StringNotEquals']['ec2:Owner']
        )
        
        if dec_allowlist == scp_allowlist:
            print(f"✓ Allowlist consistency verified: {len(dec_allowlist)} accounts match")
        else:
            print("✗ ERROR: Allowlist mismatch between policies!")
            print(f"  Declarative policy: {dec_allowlist}")
            print(f"  SCP policy: {scp_allowlist}")
            raise ValueError("Allowlist mismatch detected!")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Generate AMI governance policies from config",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate policies in audit mode (default)
  python generate_policies.py
  
  # Generate policies in enforcement mode
  python generate_policies.py --mode enabled
  
  # Use custom config location
  python generate_policies.py --config /path/to/config.json
        """
    )
    
    parser.add_argument(
        '--mode',
        choices=['audit_mode', 'enabled'],
        default='audit_mode',
        help='Enforcement mode for allowed_images_settings (default: audit_mode)'
    )
    
    parser.add_argument(
        '--config',
        default='config/ami_publishers.json',
        help='Path to config file (default: config/ami_publishers.json)'
    )
    
    args = parser.parse_args()
    
    try:
        generator = AMIPolicyGenerator(args.config)
        generator.generate_all(args.mode)
        return 0
    except Exception as e:
        print(f"\n✗ ERROR: {e}")
        return 1


if __name__ == '__main__':
    exit(main())
