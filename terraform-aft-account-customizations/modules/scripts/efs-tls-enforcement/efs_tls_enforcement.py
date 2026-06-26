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

EFS REPLICATION DESTINATION EXCLUSION:
When EFS replication is configured, the destination file system:
- Is read-only and cannot have a resource policy attached
- Appears as the Destination in the replication configuration
- Should NOT be evaluated for TLS enforcement (policy attachment is not possible)

This rule detects replication destinations by calling describe_replication_configurations
and checking whether the file system ID appears as a Destination entry. If so, the
file system is read-only and TLS enforcement is NOT_APPLICABLE.

Note: The previous approach of checking the 'aws:backup:source-resource-arn' tag was
unreliable because this tag can also appear on source (writable) EFS file systems.

MANAGED SERVICE EXCLUSION:
Certain EFS file systems are created and fully managed by AWS services such as
Amazon SageMaker. These file systems are tagged by AWS automatically and cannot
have their resource policies modified by the account owner, so TLS enforcement
via resource policy is not applicable to them.

Exclusion is controlled by MANAGED_SERVICE_EXCLUSION_TAGS (see constants below).
Any EFS file system that carries at least one of those tag keys is skipped.
To add a new service exclusion in the future, append the tag key to that list.

Known managed-service tag keys:
- ManagedByAmazonSageMakerResource  (SageMaker-provisioned EFS)
- ManagedByAwsSageMaker             (SageMaker domain/user-profile EFS)

Tag data is read directly from the AWS Config configuration item — no extra
API call is required.

TRIGGER TYPES:
This rule supports both AWS Config trigger types and dispatches on messageType:

- ScheduledNotification (periodic): the Lambda enumerates EVERY EFS file system in
  the account, evaluates each one, and reports them all in a single batched
  put_evaluations call for the whole rule. This is the trigger that keeps the
  conformance pack scored every cycle — the rule always produces results for every
  file system instead of waiting for individual resource-change notifications.

- ConfigurationItemChangeNotification: the Lambda evaluates the single resource in
  the configuration item and submits one evaluation.

Both paths share the same per-file-system decision logic (evaluate_efs_compliance),
so the two triggers always agree.

EVALUATION FLOW (per EFS file system):
1. If resource is deleted                          → NOT_APPLICABLE
2. If resource is managed by an excluded service   → NOT_APPLICABLE (AWS-managed, skip TLS check)
3. If resource is a replication destination        → NOT_APPLICABLE (read-only, skip TLS check)
4. Otherwise                                       → evaluate TLS policy enforcement

The managed-service tag check (step 3) is evaluated BEFORE the replication
destination check (step 4) on purpose. The tag check is read directly from the
Config configuration item and makes no API call, whereas the replication check
calls describe_replication_configurations. Checking the tag first lets AWS-managed
file systems (e.g. SageMaker) short-circuit without an unnecessary EFS API call —
those file systems have no replication relationship, so calling the replication
API for them only raises ReplicationNotFound and adds noise.

COMPLEMENTS:
- Guard policy (efs-validation) validates encryption-at-rest configuration
- This Lambda validates encryption-in-transit via resource policy enforcement

LOCAL TESTING:
The boto3 clients are lazily initialized to support local testing without AWS credentials.
The test suite (test_lambda.py) mocks boto3 and injects mock clients via the getter
functions get_efs_client() and get_config_client().

BOTO3 SERVICE NAME:
The boto3 service name for EFS is 'efs', not 'elasticfilesystem'.
The IAM actions use 'elasticfilesystem:*' prefix, but boto3.client() uses 'efs'.

AFT DEPLOYMENT:
This Lambda is deployed by the lambda_rule module in terraform-aft-account-customizations.
It runs in each AWS account during the AFT customization phase.
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
MAX_EVALUATIONS_PER_CALL = 100  # AWS Config put_evaluations per-request limit

# ============================================================================
# MANAGED SERVICE EXCLUSION TAGS
# ============================================================================
# EFS file systems that carry ANY of these tag keys are fully managed by an
# AWS service and cannot have their resource policies modified by the account
# owner. TLS enforcement is NOT_APPLICABLE for them.
#
# To add a new exclusion in the future, simply append the tag key here.
# Tag values are NOT checked — the presence of the key alone is sufficient.
# ============================================================================
MANAGED_SERVICE_EXCLUSION_TAGS: List[str] = [
    'ManagedByAmazonSageMakerResource',  # SageMaker-provisioned EFS (Studio/domain)
    'ManagedByAwsSageMaker',             # SageMaker domain/user-profile EFS
]

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

    Dispatches based on the AWS Config message type:
    - ScheduledNotification           → evaluate ALL EFS file systems in the account
                                         and report them in a single batched
                                         put_evaluations call for the whole rule.
    - ConfigurationItemChangeNotification (and Oversized*) → evaluate the single
                                         resource described in the configuration item.

    A periodic (ScheduledNotification) trigger is what makes the conformance pack
    score the rule every cycle: it always produces evaluation results for every EFS
    file system, instead of waiting for individual resource-change notifications
    (which leave the rule showing "no results / insufficient data" when nothing has
    changed or the only file systems are NOT_APPLICABLE).

    Args:
        event: AWS Config event
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
        message_type = invoking_event.get('messageType')
        logger.info(f"Invoking event messageType: {message_type}")

        # Periodic (scheduled) invocation: evaluate every EFS file system and submit
        # them all in one batched put_evaluations call for the whole rule.
        if message_type == 'ScheduledNotification':
            return handle_scheduled_event(event, invoking_event)

        # Otherwise: configuration-change invocation for a single resource.
        return handle_configuration_change_event(event, invoking_event)

    except Exception:
        logger.exception("Unhandled error during evaluation")
        # Re-raise to ensure Lambda reports failure
        raise


def handle_configuration_change_event(
    event: Dict[str, Any],
    invoking_event: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Evaluate a single EFS file system from a configuration-change notification.

    Args:
        event: Original Lambda event (for resultToken)
        invoking_event: Parsed invokingEvent payload

    Returns:
        Response dictionary
    """
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

    # Tags from the Config item (dict of {key: value}); used for exclusion checks
    resource_tags = configuration_item.get('tags', {})
    status = configuration_item.get('configurationItemStatus')

    compliance_type, annotation = evaluate_efs_compliance(resource_id, resource_tags, status)

    # Submit evaluation to AWS Config
    return submit_evaluation(
        event=event,
        resource_type=resource_type,
        resource_id=resource_id,
        compliance_type=compliance_type,
        annotation=clip_annotation(annotation),
        ordering_timestamp=ordering_timestamp
    )


def handle_scheduled_event(
    event: Dict[str, Any],
    invoking_event: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Evaluate ALL EFS file systems in the account for a periodic (scheduled) run.

    Enumerates every EFS file system via describe_file_systems, evaluates each one
    with the same decision logic used for change notifications, and submits the
    results to AWS Config in a single batched put_evaluations call (chunked at the
    100-evaluation API limit) under one resultToken for the whole rule.

    Args:
        event: Original Lambda event (for resultToken)
        invoking_event: Parsed invokingEvent payload (for notificationCreationTime)

    Returns:
        Response dictionary summarizing the batch
    """
    ordering_timestamp = parse_ordering_timestamp(
        invoking_event.get('notificationCreationTime')
    )

    file_systems = list_all_efs_file_systems()
    logger.info(f"Scheduled evaluation: found {len(file_systems)} EFS file system(s)")

    evaluations: List[Dict[str, Any]] = []
    for fs in file_systems:
        resource_id = fs.get('FileSystemId')
        if not resource_id:
            continue
        resource_tags = tags_list_to_dict(fs.get('Tags', []))
        compliance_type, annotation = evaluate_efs_compliance(
            resource_id, resource_tags, status=None
        )
        evaluations.append({
            'ComplianceResourceType': 'AWS::EFS::FileSystem',
            'ComplianceResourceId': resource_id,
            'ComplianceType': compliance_type,
            'Annotation': clip_annotation(annotation),
            'OrderingTimestamp': ordering_timestamp,
        })

    return submit_evaluations_batch(event, evaluations)


def evaluate_efs_compliance(
    resource_id: str,
    resource_tags: Dict[str, str],
    status: Optional[str]
) -> Tuple[str, str]:
    """
    Decide the compliance result for a single EFS file system.

    This is the shared decision logic used by BOTH the configuration-change path
    and the scheduled (periodic) path, so the two triggers always agree.

    Evaluation order (see module docstring for the full rationale):
    1. Deleted resource                → NOT_APPLICABLE
    2. Managed by an excluded service  → NOT_APPLICABLE (cheap tag check, no API call)
    3. Replication destination         → NOT_APPLICABLE (read-only, API call)
    4. Otherwise                       → evaluate the TLS resource policy

    Args:
        resource_id: EFS file system ID
        resource_tags: Tags as a {key: value} dict
        status: configurationItemStatus (None for scheduled enumeration)

    Returns:
        Tuple of (compliance_type, annotation)
    """
    if status == 'ResourceDeleted':
        return 'NOT_APPLICABLE', 'Resource has been deleted'

    if is_managed_by_excluded_service(resource_tags):
        # EFS managed by an AWS service (e.g. SageMaker) cannot have its resource
        # policy modified - TLS enforcement via policy is not applicable.
        #
        # This check is intentionally evaluated BEFORE the replication-destination
        # check: it reads tags from the Config item and makes no API call, so
        # AWS-managed file systems short-circuit here without triggering an
        # (always failing) describe_replication_configurations call.
        matched_tag = next(
            t for t in MANAGED_SERVICE_EXCLUSION_TAGS if t in resource_tags
        )
        return 'NOT_APPLICABLE', (
            f'EFS is managed by an AWS service (tag: {matched_tag}) '
            f'- TLS enforcement not applicable'
        )

    if is_efs_replication_destination(resource_id):
        # Replication destination EFS file systems are read-only and cannot have
        # resource policies - TLS enforcement does not apply to them
        return 'NOT_APPLICABLE', (
            'EFS is a replication destination (read-only) '
            '- TLS enforcement not applicable'
        )

    # Evaluate EFS file system policy
    return evaluate_efs_tls_policy(resource_id)


def list_all_efs_file_systems() -> List[Dict[str, Any]]:
    """
    Return every EFS file system in the account/region.

    Uses the describe_file_systems paginator so accounts with many file systems
    are fully enumerated. Returns the raw FileSystemDescription dicts (each with
    'FileSystemId' and 'Tags').
    """
    efs = get_efs_client()
    file_systems: List[Dict[str, Any]] = []
    paginator = efs.get_paginator('describe_file_systems')
    for page in paginator.paginate():
        file_systems.extend(page.get('FileSystems', []))
    return file_systems


def tags_list_to_dict(tags: List[Dict[str, str]]) -> Dict[str, str]:
    """
    Convert an EFS API tag list ([{'Key': k, 'Value': v}, ...]) to a {k: v} dict.

    The describe_file_systems API returns tags as a list, whereas the Config
    configuration item exposes them as a dict. The exclusion checks expect a dict,
    so normalize here.
    """
    result: Dict[str, str] = {}
    for tag in tags or []:
        key = tag.get('Key')
        if key is not None:
            result[key] = tag.get('Value', '')
    return result


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


def submit_evaluations_batch(
    event: Dict[str, Any],
    evaluations: List[Dict[str, Any]]
) -> Dict[str, Any]:
    """
    Submit a batch of evaluations to AWS Config for the whole rule in one pass.

    AWS Config's put_evaluations accepts at most MAX_EVALUATIONS_PER_CALL evaluations
    per request, so the list is chunked. All chunks share the same resultToken, so
    Config treats them as the result of a single rule run. This is what populates the
    conformance pack with results for every EFS file system on each scheduled cycle.

    Args:
        event: Original Lambda event (for resultToken)
        evaluations: List of Evaluation dicts (each with an OrderingTimestamp)

    Returns:
        Response dictionary summarizing the batch
    """
    config = get_config_client()
    result_token = event['resultToken']

    counts = {'COMPLIANT': 0, 'NON_COMPLIANT': 0, 'NOT_APPLICABLE': 0}
    for evaluation in evaluations:
        counts[evaluation['ComplianceType']] = counts.get(evaluation['ComplianceType'], 0) + 1

    if not evaluations:
        # No EFS file systems in the account: still report to Config so the rule run
        # is acknowledged (an empty evaluation set is valid and clears stale results).
        logger.info("No EFS file systems found - submitting empty evaluation set")
        config.put_evaluations(Evaluations=[], ResultToken=result_token)
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'No EFS file systems to evaluate',
                'counts': counts
            })
        }

    failed_evaluations: List[Dict[str, Any]] = []
    for i in range(0, len(evaluations), MAX_EVALUATIONS_PER_CALL):
        chunk = evaluations[i:i + MAX_EVALUATIONS_PER_CALL]
        response = config.put_evaluations(
            Evaluations=chunk,
            ResultToken=result_token
        )
        failed_evaluations.extend(response.get('FailedEvaluations', []))
        logger.info(
            f"Submitted evaluation chunk {i // MAX_EVALUATIONS_PER_CALL + 1} "
            f"({len(chunk)} evaluations); failed={len(response.get('FailedEvaluations', []))}"
        )

    logger.info(
        f"Rule evaluation complete: total={len(evaluations)} "
        f"compliant={counts['COMPLIANT']} non_compliant={counts['NON_COMPLIANT']} "
        f"not_applicable={counts['NOT_APPLICABLE']} failed={len(failed_evaluations)}"
    )

    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Rule evaluation completed successfully',
            'total': len(evaluations),
            'counts': counts,
            'failedEvaluations': failed_evaluations
        }, default=str)
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


def is_efs_replication_destination(file_system_id: str) -> bool:
    """
    Check if EFS file system is a replication destination (read-only).

    EFS replication destinations are read-only and cannot have resource policies
    attached, so TLS enforcement validation does not apply to them.

    Detection method: call describe_replication_configurations with the file system
    ID and check whether it appears as a Destination entry. The replication tab in
    the AWS Console shows Source and Destination rows; the Destination file system
    ID is what we compare against.

    Note: Checking for the 'aws:backup:source-resource-arn' tag is unreliable
    because this tag can also appear on source (writable) EFS file systems.

    Args:
        file_system_id: EFS file system ID

    Returns:
        True if EFS is a replication destination (read-only), False otherwise
    """
    efs = get_efs_client()
    try:
        response = efs.describe_replication_configurations(
            FileSystemId=file_system_id
        )
        replications = response.get('Replications', [])
        for replication in replications:
            for destination in replication.get('Destinations', []):
                if destination.get('FileSystemId') == file_system_id:
                    logger.info(
                        f"EFS {file_system_id} is a replication destination (read-only) "
                        f"- skipping TLS evaluation"
                    )
                    return True
        return False
    except efs.exceptions.ReplicationNotFound:
        # Expected, normal case: the file system simply has no replication
        # relationship, so it cannot be a replication destination. This is NOT an
        # error and must not be logged as a warning — the majority of EFS file
        # systems are not part of any replication configuration.
        logger.info(
            f"EFS {file_system_id} has no replication configuration "
            f"- not a replication destination"
        )
        return False
    except Exception as e:
        # Genuine unexpected error (throttling, access denied, etc.). Log a warning
        # and proceed with TLS evaluation rather than failing the whole rule.
        logger.warning(
            f"Could not check replication config for {file_system_id}: {str(e)} "
            f"- proceeding with evaluation"
        )
        return False


def is_managed_by_excluded_service(tags: Dict[str, str]) -> bool:
    """
    Check if an EFS file system is managed by an excluded AWS service.

    EFS file systems managed by services like SageMaker carry specific tag keys
    applied automatically by AWS. These file systems cannot have their resource
    policies modified by the account owner, so TLS enforcement is not applicable.

    To exclude additional services in the future, add their tag key to
    MANAGED_SERVICE_EXCLUSION_TAGS — no code changes needed here.

    Args:
        tags: Dict of EFS resource tags from the Config configuration item.

    Returns:
        True if the EFS carries at least one exclusion tag key, False otherwise.
    """
    for tag_key in MANAGED_SERVICE_EXCLUSION_TAGS:
        if tag_key in tags:
            logger.info(
                f"EFS has managed-service exclusion tag '{tag_key}' "
                f"- skipping TLS evaluation"
            )
            return True
    return False


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

