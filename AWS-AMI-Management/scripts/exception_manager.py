#!/usr/bin/env python3
"""
AMI Policy Exception Manager
Automates the process of managing AMI policy exceptions with expiry dates.
"""

import json
import boto3
from datetime import datetime, timedelta
from typing import Dict, List, Tuple
import argparse
import sys

class AMIExceptionManager:
    def __init__(self, parameter_name: str = "/ami-governance/active-exceptions"):
        self.ssm = boto3.client('ssm')
        self.sns = boto3.client('sns')
        self.parameter_name = parameter_name
        
    def get_active_exceptions(self) -> Dict:
        """Retrieve current exceptions from SSM Parameter Store"""
        try:
            response = self.ssm.get_parameter(Name=self.parameter_name)
            return json.loads(response['Parameter']['Value'])
        except self.ssm.exceptions.ParameterNotFound:
            return {"active_exceptions": {}, "expired_exceptions": {}}
    
    def check_expiring_exceptions(self, days_before: int = 7) -> List[Tuple[str, str]]:
        """Check for exceptions expiring within specified days"""
        exceptions = self.get_active_exceptions()
        expiring = []
        today = datetime.now().date()
        threshold = today + timedelta(days=days_before)
        
        for account_id, expiry_str in exceptions.get('active_exceptions', {}).items():
            expiry_date = datetime.strptime(expiry_str, "%Y-%m-%d").date()
            if today <= expiry_date <= threshold:
                days_remaining = (expiry_date - today).days
                expiring.append((account_id, expiry_str, days_remaining))
        
        return expiring
    
    def check_expired_exceptions(self) -> List[Tuple[str, str]]:
        """Check for expired exceptions that should be removed"""
        exceptions = self.get_active_exceptions()
        expired = []
        today = datetime.now().date()
        
        for account_id, expiry_str in exceptions.get('active_exceptions', {}).items():
            expiry_date = datetime.strptime(expiry_str, "%Y-%m-%d").date()
            if expiry_date < today:
                expired.append((account_id, expiry_str))
        
        return expired
    
    def send_expiry_notification(self, expiring: List, expired: List, topic_arn: str):
        """Send SNS notification about expiring/expired exceptions"""
        if not expiring and not expired:
            return
        
        message_parts = ["AMI Policy Exception Status Report\n", "=" * 50, "\n\n"]
        
        if expired:
            message_parts.append("⚠️  EXPIRED EXCEPTIONS (ACTION REQUIRED):\n")
            message_parts.append("-" * 50 + "\n")
            for account_id, expiry_str in expired:
                message_parts.append(f"  Account: {account_id}\n")
                message_parts.append(f"  Expired: {expiry_str}\n")
                message_parts.append(f"  Action: Remove from Terraform configuration\n\n")
        
        if expiring:
            message_parts.append("\n📅 EXPIRING SOON (within 7 days):\n")
            message_parts.append("-" * 50 + "\n")
            for account_id, expiry_str, days in expiring:
                message_parts.append(f"  Account: {account_id}\n")
                message_parts.append(f"  Expires: {expiry_str} ({days} days)\n")
                message_parts.append(f"  Action: Renew or remove exception\n\n")
        
        message_parts.append("\n" + "=" * 50 + "\n")
        message_parts.append("To update exceptions, submit a PR to:\n")
        message_parts.append("terraform-ami-governance/variables.tf\n\n")
        message_parts.append("Documentation: https://wiki.company.com/ami-governance\n")
        
        message = "".join(message_parts)
        
        try:
            self.sns.publish(
                TopicArn=topic_arn,
                Subject="AMI Policy Exception Status",
                Message=message
            )
            print(f"✅ Notification sent to {topic_arn}")
        except Exception as e:
            print(f"❌ Failed to send notification: {e}")
    
    def generate_terraform_update(self, expired: List) -> str:
        """Generate Terraform variable update to remove expired exceptions"""
        if not expired:
            return "# No expired exceptions to remove\n"
        
        tf_code = [
            "# Remove these expired exceptions from variables.tf:\n",
            "# exception_accounts = {\n"
        ]
        
        for account_id, expiry_str in expired:
            tf_code.append(f'#   "{account_id}" = "{expiry_str}"  # EXPIRED - REMOVE\n')
        
        tf_code.append("# }\n")
        
        return "".join(tf_code)


def main():
    parser = argparse.ArgumentParser(description='Manage AMI policy exceptions')
    parser.add_argument('--check', action='store_true', help='Check for expiring/expired exceptions')
    parser.add_argument('--notify', help='Send notification to SNS topic ARN')
    parser.add_argument('--days', type=int, default=7, help='Check exceptions expiring within N days')
    parser.add_argument('--parameter', default='/ami-governance/active-exceptions', 
                       help='SSM parameter name')
    
    args = parser.parse_args()
    
    manager = AMIExceptionManager(parameter_name=args.parameter)
    
    if args.check:
        print("Checking AMI policy exceptions...\n")
        
        expiring = manager.check_expiring_exceptions(days_before=args.days)
        expired = manager.check_expired_exceptions()
        
        if expired:
            print(f"⚠️  Found {len(expired)} EXPIRED exceptions:")
            for account_id, expiry_str in expired:
                print(f"  - {account_id} (expired: {expiry_str})")
            print()
            print(manager.generate_terraform_update(expired))
        
        if expiring:
            print(f"\n📅 Found {len(expiring)} exceptions expiring within {args.days} days:")
            for account_id, expiry_str, days in expiring:
                print(f"  - {account_id} expires in {days} days ({expiry_str})")
        
        if not expired and not expiring:
            print("✅ No expired or expiring exceptions found")
        
        if args.notify and (expired or expiring):
            manager.send_expiry_notification(expiring, expired, args.notify)
        
        sys.exit(1 if expired else 0)


if __name__ == '__main__':
    main()
