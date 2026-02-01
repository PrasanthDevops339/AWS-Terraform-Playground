"""
AWS Config Custom Lambda Rule: EFS TLS Enforcement

PURPOSE:
This Lambda function validates that EFS file systems enforce TLS (aws:SecureTransport) 
in their resource policies for encryption in-transit.

WHY LAMBDA IS REQUIRED:
1. EFS resource policies are NOT included in AWS Config configuration items
2. Must call efs:DescribeFileSystemPolicy API to retrieve policy
3. Must parse JSON policy document and evaluate Deny statements with conditions
4. Guard policy rules cannot make API calls or access data outside Config items

WHAT IT VALIDATES:
- EFS file system has a resource policy attached
- Policy contains Deny effect with "aws:SecureTransport": "false" condition
- Deny statement applies to EFS client actions (ClientMount, ClientWrite, ClientRootAccess)
- This ensures all connections to EFS must use TLS/encryption in transit

IMPORTANT VALIDATION:
The function validates that the Deny statement with SecureTransport=false applies to
EFS client actions, not just any actions. This prevents false positives from mis-scoped
policies (e.g., a policy that denies S3 actions when SecureTransport=false but doesn't
protect EFS client operations).

Valid action patterns for compliance:
- "*" (all actions)
- "elasticfilesystem:*" (all EFS actions)
- "elasticfilesystem:Client*" (all client actions)
- Explicit list containing elasticfilesystem:ClientMount/ClientWrite/ClientRootAccess

COMPLEMENTS:
- Guard policy (efs-is-encrypted) validates encryption-at-rest configuration
- This Lambda validates encryption-in-transit via resource policy enforcement

LOCAL TESTING:
The boto3 clients are lazily initialized to support local testing without AWS credentials.
The test suite (test_lambda.py) mocks boto3 and injects mock clients via the getter
functions get_efs_client() and get_config_client().

BOTO3 SERVICE NAME:
The boto3 service name for EFS is 'efs', not 'elasticfilesystem'.
The IAM actions use 'elasticfilesystem:*' prefix, but boto3.client() uses 'efs'.
"""

import json
import boto3
import logging
from datetime import datetime, timezone
from typing import Dict, List, Any, Optional, Tuple

# Setup logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ============================================================================
# CONSTANTS
# ============================================================================
MAX_ANNOTATION_LENGTH = 256  # AWS Config annotation limit

# ============================================================================
# LAZY CLIENT INITIALIZATION
# ============================================================================
# Clients are initialized lazily (on first use) rather than at module load time.
# This design choice enables:
# 1. Local testing without AWS credentials or boto3 installed
# 2. Avoiding NoRegionError when running tests outside AWS environment
# 3. Test suite can inject mock clients before any AWS API calls are made
# ============================================================================
efs_client: Optional[Any] = None
config_client: Optional[Any] = None

# ============================================================================
# EFS CLIENT ACTIONS TO VALIDATE
# ============================================================================
# These are the EFS actions that clients use to access file systems.
# A compliant TLS enforcement policy MUST deny these actions when
# aws:SecureTransport is false to ensure encryption in transit.
# ============================================================================
EFS_CLIENT_ACTIONS = [
    'elasticfilesystem:ClientMount',      # Mount the file system
    'elasticfilesystem:ClientWrite',       # Write to the file system
    'elasticfilesystem:ClientRootAccess'   # Root access to the file system
]


def get_efs_client():
    """
    Get or create EFS client (lazy initialization for local testing support).
    
    The boto3 service name for EFS is 'efs', not 'elasticfilesystem'.
    """
    global efs_client
    if efs_client is None:
        efs_client = boto3.client('efs')
    return efs_client


def get_config_client():
    """Get or create Config client (lazy initialization for local testing support)."""
    global config_client
    if config_client is None:
        config_client = boto3.client('config')
    return config_client


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for EFS TLS enforcement validation.
    
    Args:
        event: AWS Config event containing configuration item
        context: Lambda context object
        
    Returns:
        Response dictionary with evaluation results
    """
    try:
        # Log event keys only (avoid logging full event for large payloads)
        logger.info(f"Event keys: {list(event.keys())}")
        logger.info(f"Config rule name: {event.get('configRuleName', 'unknown')}")
        
        # Parse the invoking event - support both key formats
        raw_invoking_event = event.get('invokingEvent') or event.get('configRuleInvokingEvent')
        
        if not raw_invoking_event:
            logger.error(f"Missing invoking event key. Keys present: {list(event.keys())}")
            raise KeyError("Missing invokingEvent or configRuleInvokingEvent in event")
        
        invoking_event = json.loads(raw_invoking_event)
        configuration_item = invoking_event.get('configurationItem', {})
        
        # Validate configuration item exists and has required fields
        if not configuration_item or not configuration_item.get('resourceId'):
            logger.warning("Missing configuration item or resource ID")
            return submit_not_applicable_evaluation(
                event,
                resource_type='AWS::EFS::FileSystem',
                resource_id='UNKNOWN',
                annotation='Missing configuration item or resource ID in event'
            )
        
        # Extract essential information
        resource_id = configuration_item.get('resourceId')
        resource_type = configuration_item.get('resourceType')
        
        # Parse timestamp safely
        ordering_timestamp = parse_ordering_timestamp(
            configuration_item.get('configurationItemCaptureTime')
        )
        
        # Handle non-target resource types gracefully (NOT_APPLICABLE instead of error)
        if resource_type != 'AWS::EFS::FileSystem':
            logger.info(f"Non-target resource type: {resource_type}")
            return submit_evaluation(
                event=event,
                resource_type=resource_type,
                resource_id=resource_id,
                compliance_type='NOT_APPLICABLE',
                annotation=f'Resource type {resource_type} is not evaluated by this rule',
                ordering_timestamp=ordering_timestamp
            )
        
        # Handle resource deletion
        if configuration_item.get('configurationItemStatus') == 'ResourceDeleted':
            compliance_type = 'NOT_APPLICABLE'
            annotation = 'Resource has been deleted'
        else:
            # Evaluate EFS file system policy
            compliance_type, annotation = evaluate_efs_tls_policy(resource_id)
        
        # Clip annotation to AWS Config limit
        annotation = clip_annotation(annotation)
        
        # Submit evaluation to AWS Config
        return submit_evaluation(
            event=event,
            resource_type=resource_type,
            resource_id=resource_id,
            compliance_type=compliance_type,
            annotation=annotation,
            ordering_timestamp=ordering_timestamp
        )
        
    except Exception as e:
        logger.exception("Unhandled error during evaluation")
        # Re-raise to ensure Lambda reports failure
        raise


def clip_annotation(text: str, max_len: int = MAX_ANNOTATION_LENGTH) -> str:
    """Clip annotation to AWS Config maximum length."""
    if len(text) <= max_len:
        return text
    return text[:max_len - 3] + "..."


def parse_ordering_timestamp(timestamp_str: Optional[str]) -> datetime:
    """
    Parse configuration item timestamp to datetime object.
    
    AWS SDK expects datetime, not string for OrderingTimestamp.
    
    Args:
        timestamp_str: ISO format timestamp string from Config
        
    Returns:
        datetime object (defaults to now if parsing fails)
    """
    if not timestamp_str:
        return datetime.now(timezone.utc)
    
    try:
        # Handle ISO format with Z suffix
        return datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
    except (ValueError, AttributeError) as e:
        logger.warning(f"Failed to parse timestamp '{timestamp_str}': {e}")
        return datetime.now(timezone.utc)


def submit_evaluation(
    event: Dict[str, Any],
    resource_type: str,
    resource_id: str,
    compliance_type: str,
    annotation: str,
    ordering_timestamp: datetime
) -> Dict[str, Any]:
    """
    Submit evaluation result to AWS Config.
    
    Args:
        event: Original Lambda event (for resultToken)
        resource_type: AWS resource type
        resource_id: Resource identifier
        compliance_type: COMPLIANT, NON_COMPLIANT, or NOT_APPLICABLE
        annotation: Evaluation annotation
        ordering_timestamp: Timestamp for ordering evaluations
        
    Returns:
        Response dictionary
    """
    evaluation = {
        'ComplianceResourceType': resource_type,
        'ComplianceResourceId': resource_id,
        'ComplianceType': compliance_type,
        'Annotation': annotation,
        'OrderingTimestamp': ordering_timestamp
    }
    
    # Submit evaluation to AWS Config
    response = get_config_client().put_evaluations(
        Evaluations=[evaluation],
        ResultToken=event['resultToken']
    )
    
    logger.info(f"Evaluation submitted: compliance={compliance_type}, resource={resource_id}")
    logger.info(f"PutEvaluations response: {json.dumps(response, default=str)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Evaluation completed successfully',
            'evaluation': {
                **evaluation,
                'OrderingTimestamp': ordering_timestamp.isoformat()
            }
        })
    }


def submit_not_applicable_evaluation(
    event: Dict[str, Any],
    resource_type: str,
    resource_id: str,
    annotation: str
) -> Dict[str, Any]:
    """Submit NOT_APPLICABLE evaluation for edge cases."""
    return submit_evaluation(
        event=event,
        resource_type=resource_type,
        resource_id=resource_id,
        compliance_type='NOT_APPLICABLE',
        annotation=clip_annotation(annotation),
        ordering_timestamp=datetime.now(timezone.utc)
    )


def evaluate_efs_tls_policy(file_system_id: str) -> Tuple[str, str]:
    """
    Evaluate if EFS file system policy enforces TLS (aws:SecureTransport).
    
    Args:
        file_system_id: EFS file system ID
        
    Returns:
        Tuple of (compliance_type, annotation)
    """
    efs = get_efs_client()
    try:
        # Attempt to retrieve file system policy
        response = efs.describe_file_system_policy(FileSystemId=file_system_id)
        policy_json = response.get('Policy')
        
        if not policy_json:
            return 'NON_COMPLIANT', 'EFS file system has no policy defined'
        
        # Parse the policy
        policy = json.loads(policy_json)
        logger.info(f"EFS Policy for {file_system_id}: policy retrieved successfully")
        
        # Check if policy enforces SecureTransport for EFS client actions
        if is_secure_transport_enforced(policy, file_system_id):
            return 'COMPLIANT', 'EFS file system policy enforces TLS (aws:SecureTransport) for client actions'
        else:
            return 'NON_COMPLIANT', 'EFS policy does not enforce TLS for EFS client actions (ClientMount/ClientWrite/ClientRootAccess)'
            
    except efs.exceptions.PolicyNotFound:
        logger.warning(f"No policy found for EFS file system: {file_system_id}")
        return 'NON_COMPLIANT', 'EFS file system has no policy - TLS enforcement not configured'
        
    except efs.exceptions.FileSystemNotFound:
        logger.error(f"EFS file system not found: {file_system_id}")
        return 'NON_COMPLIANT', f'EFS file system not found: {file_system_id}'
        
    except Exception as e:
        logger.error(f"Error evaluating EFS policy: {str(e)}", exc_info=True)
        # Clip error message to prevent annotation overflow
        error_msg = clip_annotation(f'Error evaluating EFS policy: {str(e)}')
        return 'NON_COMPLIANT', error_msg


def is_secure_transport_enforced(policy: Dict[str, Any], file_system_id: str = None) -> bool:
    """
    Check if the EFS policy enforces aws:SecureTransport for EFS client actions.
    
    The policy must have a Deny statement that:
    1. Denies access when aws:SecureTransport is false
    2. Applies to EFS client actions (ClientMount, ClientWrite, ClientRootAccess)
       OR applies to all actions ("*" or "elasticfilesystem:*")
    
    Args:
        policy: Parsed EFS policy dictionary
        file_system_id: Optional EFS file system ID for resource validation
        
    Returns:
        True if SecureTransport is enforced for client actions, False otherwise
    """
    statements = policy.get('Statement', [])
    
    for statement in statements:
        effect = statement.get('Effect', '')
        condition = statement.get('Condition', {})
        
        # Only check Deny statements
        if effect != 'Deny':
            continue
        
        # Check for SecureTransport condition (Bool or BoolIfExists)
        bool_condition = condition.get('Bool', {})
        bool_if_exists = condition.get('BoolIfExists', {})
        
        secure_transport_check = (
            bool_condition.get('aws:SecureTransport') == 'false' or
            bool_condition.get('aws:SecureTransport') is False or
            bool_if_exists.get('aws:SecureTransport') == 'false' or
            bool_if_exists.get('aws:SecureTransport') is False
        )
        
        if not secure_transport_check:
            continue
        
        # Validate that the Deny applies to EFS client actions
        if not _validates_client_actions(statement):
            logger.warning(
                "Found Deny with SecureTransport=false but does not apply to EFS client actions"
            )
            continue
        
        logger.info(
            "Found compliant Deny statement: SecureTransport=false with EFS client actions"
        )
        return True
    
    logger.warning("No valid SecureTransport enforcement found for EFS client actions")
    return False


def _validates_client_actions(statement: Dict[str, Any]) -> bool:
    """
    Check if a policy statement applies to EFS client actions.
    
    Valid patterns:
    - Action: "*" (all actions)
    - Action: "elasticfilesystem:*" (all EFS actions)
    - Action includes elasticfilesystem:ClientMount, ClientWrite, or ClientRootAccess
    - NotAction that doesn't exclude client actions
    
    Args:
        statement: Policy statement dictionary
        
    Returns:
        True if statement applies to EFS client actions
    """
    actions = statement.get('Action', [])
    not_actions = statement.get('NotAction', [])
    
    # Normalize to list
    if isinstance(actions, str):
        actions = [actions]
    if isinstance(not_actions, str):
        not_actions = [not_actions]
    
    # If using NotAction, check that client actions are not excluded
    if not_actions:
        for not_action in not_actions:
            for client_action in EFS_CLIENT_ACTIONS:
                if _action_matches(not_action, client_action):
                    # Client action is excluded, so this statement doesn't apply
                    logger.warning(f"Client action {client_action} excluded by NotAction")
                    return False
        # NotAction doesn't exclude client actions, so they are covered
        return True
    
    # Check if any action covers EFS client actions
    for action in actions:
        # Wildcard covers all actions
        if action == '*':
            logger.info("Action '*' covers all EFS client actions")
            return True
        
        # elasticfilesystem:* covers all EFS actions
        if action.lower() == 'elasticfilesystem:*':
            logger.info("Action 'elasticfilesystem:*' covers all EFS client actions")
            return True
        
        # Check for specific client actions
        for client_action in EFS_CLIENT_ACTIONS:
            if _action_matches(action, client_action):
                logger.info(f"Action '{action}' matches client action '{client_action}'")
                return True
    
    logger.warning(f"Actions {actions} do not cover EFS client actions")
    return False


def _action_matches(pattern: str, action: str) -> bool:
    """
    Check if an action pattern matches a specific action.
    
    Supports:
    - Exact match
    - Wildcard patterns (e.g., elasticfilesystem:Client*)
    - Case-insensitive comparison
    
    Args:
        pattern: Action pattern from policy (may contain wildcards)
        action: Specific action to check
        
    Returns:
        True if pattern matches action
    """
    pattern_lower = pattern.lower()
    action_lower = action.lower()
    
    # Exact match
    if pattern_lower == action_lower:
        return True
    
    # Wildcard match
    if '*' in pattern_lower:
        # Simple wildcard matching: convert pattern to prefix match
        # e.g., "elasticfilesystem:Client*" matches "elasticfilesystem:ClientMount"
        prefix = pattern_lower.replace('*', '')
        if action_lower.startswith(prefix):
            return True
        
        # Handle more complex patterns like "elasticfilesystem:*"
        if pattern_lower.endswith('*'):
            prefix = pattern_lower[:-1]
            if action_lower.startswith(prefix):
                return True
    
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
