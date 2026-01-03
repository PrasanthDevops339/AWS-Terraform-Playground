#!/usr/bin/env python3
"""
AMI Policy Validator

Validates ami_publishers.json configuration and generated policies.
Used in CI pipeline to ensure policy integrity.

Checks:
1. JSON formatting and schema validation
2. No expired exceptions in allowlist
3. Allowlist consistency between declarative policy and SCP
4. Required fields present and valid
"""

import json
import sys
from datetime import date
from pathlib import Path
from typing import List, Tuple


class PolicyValidator:
    """Validate AMI governance configuration and generated policies."""
    
    def __init__(self):
        self.errors: List[str] = []
        self.warnings: List[str] = []
        
    def validate_config(self, config_path: str = "config/ami_publishers.json") -> bool:
        """Validate configuration file."""
        print(f"\n{'='*70}")
        print("VALIDATING CONFIGURATION")
        print(f"{'='*70}")
        
        config_file = Path(config_path)
        
        # Check file exists
        if not config_file.exists():
            self.errors.append(f"Config file not found: {config_path}")
            return False
        
        # Load and parse JSON
        try:
            with open(config_file, 'r') as f:
                config = json.load(f)
            print(f"✓ Valid JSON format: {config_path}")
        except json.JSONDecodeError as e:
            self.errors.append(f"Invalid JSON in {config_path}: {e}")
            return False
        
        # Validate required fields
        required_fields = {
            'ops_publisher_account': dict,
            'vendor_publisher_accounts': list,
            'exception_accounts': list,
            'policy_config': dict
        }
        
        for field, expected_type in required_fields.items():
            if field not in config:
                self.errors.append(f"Missing required field: {field}")
            elif not isinstance(config[field], expected_type):
                self.errors.append(
                    f"Field {field} must be {expected_type.__name__}, got {type(config[field]).__name__}"
                )
        
        if self.errors:
            return False
        
        print("✓ All required fields present")
        
        # Validate ops publisher
        if 'account_id' not in config['ops_publisher_account']:
            self.errors.append("ops_publisher_account missing account_id")
        
        # Validate vendor publishers
        for i, vendor in enumerate(config['vendor_publisher_accounts']):
            if 'account_id' not in vendor:
                self.errors.append(f"vendor_publisher_accounts[{i}] missing account_id")
            if 'vendor_name' not in vendor:
                self.warnings.append(f"vendor_publisher_accounts[{i}] missing vendor_name")
        
        print(f"✓ Ops publisher: {config['ops_publisher_account']['account_id']}")
        print(f"✓ Vendor publishers: {len(config['vendor_publisher_accounts'])}")
        
        # Validate exceptions
        today = date.today().isoformat()
        active_exceptions = 0
        expired_exceptions = 0
        
        for i, exception in enumerate(config['exception_accounts']):
            if 'account_id' not in exception:
                self.errors.append(f"exception_accounts[{i}] missing account_id")
                continue
            
            if 'expires_on' not in exception:
                self.errors.append(
                    f"exception_accounts[{i}] ({exception['account_id']}) missing expires_on"
                )
                continue
            
            if 'reason' not in exception:
                self.warnings.append(
                    f"exception_accounts[{i}] ({exception['account_id']}) missing reason"
                )
            
            if 'ticket' not in exception:
                self.warnings.append(
                    f"exception_accounts[{i}] ({exception['account_id']}) missing ticket"
                )
            
            # Check expiry
            expires_on = exception['expires_on']
            if expires_on < today:
                expired_exceptions += 1
                self.errors.append(
                    f"EXPIRED exception found: {exception['account_id']} "
                    f"(expired {expires_on}) - Remove from config or extend expiry"
                )
            else:
                active_exceptions += 1
                print(f"  ✓ Active exception: {exception['account_id']} expires {expires_on}")
        
        print(f"✓ Active exceptions: {active_exceptions}")
        if expired_exceptions > 0:
            print(f"✗ Expired exceptions: {expired_exceptions} (must be removed)")
        
        return len(self.errors) == 0
    
    def validate_generated_policies(self) -> bool:
        """Validate generated policy files."""
        print(f"\n{'='*70}")
        print("VALIDATING GENERATED POLICIES")
        print(f"{'='*70}")
        
        declarative_path = Path("dist/declarative-policy-ec2.json")
        scp_path = Path("dist/scp-ami-guardrail.json")
        
        # Check files exist
        if not declarative_path.exists():
            self.errors.append(f"Generated policy not found: {declarative_path}")
            self.errors.append("Run: python scripts/generate_policies.py")
            return False
        
        if not scp_path.exists():
            self.errors.append(f"Generated policy not found: {scp_path}")
            self.errors.append("Run: python scripts/generate_policies.py")
            return False
        
        # Load policies
        try:
            with open(declarative_path, 'r') as f:
                declarative_policy = json.load(f)
            print(f"✓ Valid JSON: {declarative_path}")
        except json.JSONDecodeError as e:
            self.errors.append(f"Invalid JSON in {declarative_path}: {e}")
            return False
        
        try:
            with open(scp_path, 'r') as f:
                scp_policy = json.load(f)
            print(f"✓ Valid JSON: {scp_path}")
        except json.JSONDecodeError as e:
            self.errors.append(f"Invalid JSON in {scp_path}: {e}")
            return False
        
        # Extract allowlists
        try:
            dec_allowlist = set(
                declarative_policy['content']['ec2']['ec2_attributes']
                ['allowed_images_settings']['image_criteria']['criteria_1']
                ['allowed_image_providers']
            )
        except KeyError as e:
            self.errors.append(f"Declarative policy missing expected structure: {e}")
            return False
        
        try:
            scp_allowlist = set(
                scp_policy['Statement'][0]['Condition']['StringNotEquals']['ec2:Owner']
            )
        except (KeyError, IndexError) as e:
            self.errors.append(f"SCP policy missing expected structure: {e}")
            return False
        
        # Check consistency
        if dec_allowlist != scp_allowlist:
            self.errors.append("ALLOWLIST MISMATCH between declarative policy and SCP!")
            self.errors.append(f"  Declarative policy accounts: {sorted(dec_allowlist)}")
            self.errors.append(f"  SCP policy accounts: {sorted(scp_allowlist)}")
            self.errors.append("  Regenerate policies: python scripts/generate_policies.py")
            return False
        
        print(f"✓ Allowlist consistency verified")
        print(f"  Total approved accounts: {len(dec_allowlist)}")
        print(f"  Accounts: {', '.join(sorted(dec_allowlist))}")
        
        # Validate enforcement mode
        enforcement_mode = declarative_policy['content']['ec2']['ec2_attributes']['allowed_images_settings']['state']
        print(f"✓ Enforcement mode: {enforcement_mode}")
        
        if enforcement_mode not in ['audit_mode', 'enabled']:
            self.warnings.append(f"Unexpected enforcement mode: {enforcement_mode}")
        
        # Check public AMI blocking
        public_ami_state = declarative_policy['content']['ec2']['ec2_attributes']['image_block_public_access']['state']
        if public_ami_state != 'block_new_sharing':
            self.warnings.append(
                f"Public AMI blocking not set to 'block_new_sharing': {public_ami_state}"
            )
        else:
            print(f"✓ Public AMI blocking: {public_ami_state}")
        
        return len(self.errors) == 0
    
    def print_summary(self) -> bool:
        """Print validation summary and return overall status."""
        print(f"\n{'='*70}")
        print("VALIDATION SUMMARY")
        print(f"{'='*70}")
        
        if self.warnings:
            print(f"\n⚠ WARNINGS ({len(self.warnings)}):")
            for warning in self.warnings:
                print(f"  • {warning}")
        
        if self.errors:
            print(f"\n✗ ERRORS ({len(self.errors)}):")
            for error in self.errors:
                print(f"  • {error}")
            print(f"\n{'='*70}")
            print("❌ VALIDATION FAILED")
            print(f"{'='*70}\n")
            return False
        
        print(f"\n{'='*70}")
        print("✅ VALIDATION PASSED")
        print(f"{'='*70}\n")
        return True


def main():
    """Main entry point."""
    validator = PolicyValidator()
    
    # Run validations
    config_valid = validator.validate_config()
    policies_valid = validator.validate_generated_policies()
    
    # Print summary
    success = validator.print_summary()
    
    return 0 if success else 1


if __name__ == '__main__':
    sys.exit(main())
