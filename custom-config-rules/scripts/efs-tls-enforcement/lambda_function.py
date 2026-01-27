"""
AWS Config Custom Lambda Rule: EFS TLS Enforcement

PURPOSE:
This Lambda function validates that EFS file systems enforce TLS (aws:SecureTransport) 
in their resource policies for encryption in-transit.

WHY LAMBDA IS REQUIRED:
1. EFS resource policies are NOT included in AWS Config configuration items
2. Must call elasticfilesystem:DescribeFileSystemPolicy API to retrieve policy
3. Must parse JSON policy document and evaluate Deny statements with conditions
4. Guard policy rules cannot make API calls or access data outside Config items

WHAT IT VALIDATES:
- EFS file system has a resource policy attached
- Policy contains Deny effect with "aws:SecureTransport": "false" condition
- This ensures all connections to EFS must use TLS/encryption in transit

COMPLEMENTS:
- Guard policy (efs-is-encrypted) validates encryption-at-rest configuration
- This Lambda validates encryption-in-transit via resource policy enforcement
"""

import json
import boto3
import logging
from datetime import datetime
from typing import Dict, List, Any

# Setup logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
efs_client = boto3.client('elasticfilesystem')
config_client = boto3.client('config')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for EFS TLS enforcement validation.
    
    Args:
        event: AWS Config event containing configuration item
        context: Lambda context object
        
    Returns:
        Response dictionary with evaluation results
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    # Parse the invoking event
    invoking_event = json.loads(event['configRuleInvokingEvent'])
    configuration_item = invoking_event.get('configurationItem', {})
    
    # Extract essential information
    resource_id = configuration_item.get('resourceId')
    resource_type = configuration_item.get('resourceType')
    configuration_item_capture_time = configuration_item.get('configurationItemCaptureTime')
    
    # Validate resource type
    if resource_type != 'AWS::EFS::FileSystem':
        logger.error(f"Invalid resource type: {resource_type}")
        return build_error_response(f"Invalid resource type: {resource_type}")
    
    # Handle resource deletion
    if configuration_item.get('configurationItemStatus') == 'ResourceDeleted':
        compliance_type = 'NOT_APPLICABLE'
        annotation = 'Resource has been deleted'
    else:
        # Evaluate EFS file system policy
        compliance_type, annotation = evaluate_efs_tls_policy(resource_id)
    
    # Build and submit evaluation
    evaluation = {
        'ComplianceResourceType': resource_type,
        'ComplianceResourceId': resource_id,
        'ComplianceType': compliance_type,
        'Annotation': annotation,
        'OrderingTimestamp': configuration_item_capture_time
    }
    
    # Submit evaluation to AWS Config
    response = config_client.put_evaluations(
        Evaluations=[evaluation],
        ResultToken=event['resultToken']
    )
    
    logger.info(f"Evaluation submitted: {json.dumps(evaluation)}")
    logger.info(f"PutEvaluations response: {json.dumps(response, default=str)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Evaluation completed successfully',
            'evaluation': evaluation
        })
    }


def evaluate_efs_tls_policy(file_system_id: str) -> tuple:
    """
    Evaluate if EFS file system policy enforces TLS (aws:SecureTransport).
    
    Args:
        file_system_id: EFS file system ID
        
    Returns:
        Tuple of (compliance_type, annotation)
    """
    try:
        # Attempt to retrieve file system policy
        response = efs_client.describe_file_system_policy(FileSystemId=file_system_id)
        policy_json = response.get('Policy')
        
        if not policy_json:
            return 'NON_COMPLIANT', 'EFS file system has no policy defined'
        
        # Parse the policy
        policy = json.loads(policy_json)
        logger.info(f"EFS Policy for {file_system_id}: {json.dumps(policy)}")
        
        # Check if policy enforces SecureTransport
        if is_secure_transport_enforced(policy):
            return 'COMPLIANT', 'EFS file system policy enforces TLS (aws:SecureTransport)'
        else:
            return 'NON_COMPLIANT', 'EFS file system policy does not enforce TLS (aws:SecureTransport)'
            
    except efs_client.exceptions.PolicyNotFoundException:
        logger.warning(f"No policy found for EFS file system: {file_system_id}")
        return 'NON_COMPLIANT', 'EFS file system has no policy - TLS enforcement not configured'
        
    except efs_client.exceptions.FileSystemNotFound:
        logger.error(f"EFS file system not found: {file_system_id}")
        return 'NON_COMPLIANT', f'EFS file system not found: {file_system_id}'
        
    except Exception as e:
        logger.error(f"Error evaluating EFS policy: {str(e)}", exc_info=True)
        return 'NON_COMPLIANT', f'Error evaluating EFS policy: {str(e)}'


def is_secure_transport_enforced(policy: Dict[str, Any]) -> bool:
    """
    Check if the EFS policy enforces aws:SecureTransport.
    
    The policy should have a statement that denies access when 
    aws:SecureTransport is false.
    
    Args:
        policy: Parsed EFS policy dictionary
        
    Returns:
        True if SecureTransport is enforced, False otherwise
    """
    statements = policy.get('Statement', [])
    
    for statement in statements:
        effect = statement.get('Effect', '')
        condition = statement.get('Condition', {})
        
        # Check for Deny effect with SecureTransport condition
        if effect == 'Deny':
            # Check for Bool condition with aws:SecureTransport
            bool_condition = condition.get('Bool', {})
            secure_transport = bool_condition.get('aws:SecureTransport')
            
            # If SecureTransport is explicitly set to false (meaning deny non-TLS), it's compliant
            if secure_transport == 'false' or secure_transport is False:
                logger.info("Found Deny statement with aws:SecureTransport=false")
                return True
            
            # Also check for NumericLessThan or StringEquals patterns
            if 'aws:SecureTransport' in str(condition):
                logger.info("Found SecureTransport condition in policy")
                # Additional validation can be added here
        
        # Alternative: Check for Allow effect that requires SecureTransport=true
        if effect == 'Allow':
            bool_condition = condition.get('Bool', {})
            secure_transport = bool_condition.get('aws:SecureTransport')
            
            # If only allowing when SecureTransport is true
            if secure_transport == 'true' or secure_transport is True:
                # Need to verify there's a corresponding Deny for false case
                # or that this is the only statement
                logger.info("Found Allow statement requiring aws:SecureTransport=true")
                # This alone may not be sufficient - best practice is Deny when false
    
    # Check if there's a blanket Deny for SecureTransport=false
    for statement in statements:
        if statement.get('Effect') == 'Deny':
            condition = statement.get('Condition', {})
            bool_if_exists = condition.get('BoolIfExists', {})
            bool_condition = condition.get('Bool', {})
            
            # Check both Bool and BoolIfExists
            secure_transport_check = (
                bool_condition.get('aws:SecureTransport') == 'false' or
                bool_condition.get('aws:SecureTransport') is False or
                bool_if_exists.get('aws:SecureTransport') == 'false' or
                bool_if_exists.get('aws:SecureTransport') is False
            )
            
            if secure_transport_check:
                return True
    
    logger.warning("No valid SecureTransport enforcement found in policy")
    return False


def build_error_response(error_message: str) -> Dict[str, Any]:
    """
    Build an error response.
    
    Args:
        error_message: Error message to include
        
    Returns:
        Error response dictionary
    """
    return {
        'statusCode': 400,
        'body': json.dumps({
            'error': error_message
        })
    }
