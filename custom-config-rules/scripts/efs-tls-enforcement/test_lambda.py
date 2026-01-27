#!/usr/bin/env python3
"""
Test script for EFS TLS Enforcement Lambda Function
Tests various scenarios for compliance validation
"""

import json
import sys
from pathlib import Path

# Add the lambda function to the path
sys.path.insert(0, str(Path(__file__).parent))

# Mock boto3 for testing
class MockEFSClient:
    def __init__(self, scenario):
        self.scenario = scenario
    
    def describe_file_system_policy(self, FileSystemId):
        if self.scenario == "no_policy":
            from botocore.exceptions import ClientError
            error = ClientError(
                {'Error': {'Code': 'PolicyNotFound', 'Message': 'Policy not found'}},
                'DescribeFileSystemPolicy'
            )
            raise error
        elif self.scenario == "compliant_deny":
            return {
                'Policy': json.dumps({
                    "Version": "2012-10-17",
                    "Statement": [
                        {
                            "Sid": "DenyUnencryptedTransport",
                            "Effect": "Deny",
                            "Principal": "*",
                            "Action": "*",
                            "Resource": "*",
                            "Condition": {
                                "Bool": {
                                    "aws:SecureTransport": "false"
                                }
                            }
                        }
                    ]
                })
            }
        elif self.scenario == "non_compliant":
            return {
                'Policy': json.dumps({
                    "Version": "2012-10-17",
                    "Statement": [
                        {
                            "Sid": "AllowAll",
                            "Effect": "Allow",
                            "Principal": "*",
                            "Action": "*",
                            "Resource": "*"
                        }
                    ]
                })
            }
        elif self.scenario == "compliant_bool_if_exists":
            return {
                'Policy': json.dumps({
                    "Version": "2012-10-17",
                    "Statement": [
                        {
                            "Sid": "DenyUnencryptedTransport",
                            "Effect": "Deny",
                            "Principal": "*",
                            "Action": "*",
                            "Resource": "*",
                            "Condition": {
                                "BoolIfExists": {
                                    "aws:SecureTransport": "false"
                                }
                            }
                        }
                    ]
                })
            }


class MockConfigClient:
    def __init__(self):
        self.evaluations = []
    
    def put_evaluations(self, Evaluations, ResultToken):
        self.evaluations.extend(Evaluations)
        return {
            'FailedEvaluations': []
        }


def run_test(scenario_name, scenario, expected_compliance):
    """Run a test scenario"""
    print(f"\n{'='*60}")
    print(f"Testing: {scenario_name}")
    print(f"{'='*60}")
    
    # Import the lambda function module
    import lambda_function
    
    # Mock the boto3 clients
    lambda_function.efs_client = MockEFSClient(scenario)
    mock_config = MockConfigClient()
    lambda_function.config_client = mock_config
    
    # Create test event
    event = {
        'configRuleInvokingEvent': json.dumps({
            'configurationItem': {
                'resourceId': 'fs-12345678',
                'resourceType': 'AWS::EFS::FileSystem',
                'configurationItemCaptureTime': '2026-01-26T12:00:00.000Z',
                'configurationItemStatus': 'OK'
            }
        }),
        'resultToken': 'test-token-123'
    }
    
    # Run the lambda function
    try:
        result = lambda_function.lambda_handler(event, None)
        
        # Check the evaluation
        if mock_config.evaluations:
            evaluation = mock_config.evaluations[0]
            compliance = evaluation['ComplianceType']
            annotation = evaluation['Annotation']
            
            print(f"Compliance: {compliance}")
            print(f"Annotation: {annotation}")
            
            if compliance == expected_compliance:
                print(f"✅ PASSED - Expected {expected_compliance}, got {compliance}")
                return True
            else:
                print(f"❌ FAILED - Expected {expected_compliance}, got {compliance}")
                return False
        else:
            print("❌ FAILED - No evaluation submitted")
            return False
            
    except Exception as e:
        print(f"❌ FAILED - Exception: {str(e)}")
        import traceback
        traceback.print_exc()
        return False


def main():
    """Run all test scenarios"""
    print("\n" + "="*60)
    print("EFS TLS Enforcement Lambda Function - Test Suite")
    print("="*60)
    
    test_scenarios = [
        {
            'name': 'No Policy (Should be NON_COMPLIANT)',
            'scenario': 'no_policy',
            'expected': 'NON_COMPLIANT'
        },
        {
            'name': 'Compliant Policy with Deny + SecureTransport=false',
            'scenario': 'compliant_deny',
            'expected': 'COMPLIANT'
        },
        {
            'name': 'Non-Compliant Policy (No SecureTransport enforcement)',
            'scenario': 'non_compliant',
            'expected': 'NON_COMPLIANT'
        },
        {
            'name': 'Compliant Policy with BoolIfExists condition',
            'scenario': 'compliant_bool_if_exists',
            'expected': 'COMPLIANT'
        }
    ]
    
    results = []
    for test in test_scenarios:
        passed = run_test(test['name'], test['scenario'], test['expected'])
        results.append((test['name'], passed))
    
    # Print summary
    print("\n" + "="*60)
    print("Test Summary")
    print("="*60)
    
    passed_count = sum(1 for _, passed in results if passed)
    total_count = len(results)
    
    for name, passed in results:
        status = "✅ PASSED" if passed else "❌ FAILED"
        print(f"{status}: {name}")
    
    print(f"\nTotal: {passed_count}/{total_count} tests passed")
    
    if passed_count == total_count:
        print("\n🎉 All tests passed!")
        return 0
    else:
        print(f"\n⚠️  {total_count - passed_count} test(s) failed")
        return 1


if __name__ == '__main__':
    sys.exit(main())
