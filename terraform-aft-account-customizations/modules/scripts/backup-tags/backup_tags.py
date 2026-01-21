"""
AWS Config Custom Rule - Backup Schedule Tag Validation

Purpose:
    Validates that AWS resources have required backup schedule tags with approved values.
    Enforces organizational backup policies by checking tag presence and values.

Tags Validated:
    - ops:backupschedule1, ops:backupschedule2, ops:backupschedule3
    - Valid values: none, hourly1day, hourly8day, 1xday14day, 1xday30day, 
                    1xweek60day, 1xweek120day, 1xmonth365day

Triggered by:
    AWS Config on resource configuration changes (EC2, RDS, EBS volumes)

Compliance Results:
    - COMPLIANT: All required tags present with valid values
    - NON_COMPLIANT: Missing tags or invalid tag values
"""

import json
import boto3

# Load tag configuration from JSON file
# This file defines required tags and their accepted values
jsonfile = open('backup_tags.json', 'r')
jsondat = jsonfile.read()

# Parse JSON configuration
obj = json.loads(jsondat)
print(obj['required_tags'])


def evaluate_compliance(configuration_item, rule_parameters):
    """
    Evaluates resource compliance against backup tagging requirements.
    
    Args:
        configuration_item (dict): Resource configuration from AWS Config
        rule_parameters (dict): Rule parameters containing required_tags definition
        
    Returns:
        dict: Compliance result with type (COMPLIANT/NON_COMPLIANT) and annotation
        
    Validation Logic:
        1. Check if all required tag keys are present
        2. Check if tag values match accepted values list
        3. Return appropriate compliance status
    """
    # Extract required tags definition and current resource tags
    required_tags = rule_parameters.get("required_tags", {})
    resource_tags = configuration_item.get("tags", {}) or {}

    # Initialize tracking lists
    non_compliant_tags = []      # Tags with invalid values
    approved_tag_keys = []       # List of expected tag keys
    missing_tag_keys = []        # Tags that should exist but don't

    # Build list of required tag keys
    for tag_name, accepted_values in required_tags.items():
        approved_tag_keys.append(tag_name)

    # Check for missing tags (tag keys that don't exist on resource)
    for x in approved_tag_keys:
        if x not in resource_tags:
            missing_tag_keys.append(x)

    # If any required tags are missing, return NON_COMPLIANT immediately
    if missing_tag_keys:
        return {
            "compliance_type": "NON_COMPLIANT",
            "annotation": f"Required backup tag keys are missing: {', '.join(missing_tag_keys)}"
        }

    # Check if tag values match the approved values list
    for tag_name, accepted_values in required_tags.items():
        if tag_name in resource_tags and resource_tags[tag_name] not in accepted_values:
            non_compliant_tags.append(f"{tag_name}={resource_tags[tag_name]}")

    # If any tags have invalid values, return NON_COMPLIANT
    if non_compliant_tags:
        return {
            "compliance_type": "NON_COMPLIANT",
            "annotation": f"Tag values do not match accepted values: {', '.join(non_compliant_tags)}"
        }

    # All checks passed - resource is compliant
    return {
        "compliance_type": "COMPLIANT",
        "annotation": "All required tags have values matching accepted values."
    }


def lambda_handler(event, context):
    """
    AWS Lambda handler function invoked by AWS Config.
    
    Args:
        event (dict): AWS Config event containing:
            - invokingEvent: Resource configuration details
            - resultToken: Token to report evaluation results back to Config
        context (object): Lambda context object
        
    Returns:
        dict: AWS Config put_evaluations API response
        
    Flow:
        1. Parse the Config event to extract resource configuration
        2. Evaluate compliance using backup tag rules
        3. Report results back to AWS Config using put_evaluations API
        4. Log the evaluation result
    """
    # Log the full event for debugging
    print(event)
    
    # Extract resource configuration from the Config event
    invoking_event = json.loads(event["invokingEvent"])
    configuration_item = invoking_event["configurationItem"]
    
    # Load rule parameters (tag requirements) from JSON file
    rule_parameters = json.loads(jsondat)

    # Evaluate resource compliance against tag requirements
    evaluation = evaluate_compliance(configuration_item, rule_parameters)

    # Initialize AWS Config client to report evaluation results
    config = boto3.client("config")
    
    # Send compliance evaluation back to AWS Config
    response = config.put_evaluations(
        Evaluations=[
            {
                "ComplianceResourceType": configuration_item["resourceType"],  # e.g., AWS::EC2::Instance
                "ComplianceResourceId": configuration_item["resourceId"],      # e.g., i-1234567890abcdef0
                "ComplianceType": evaluation["compliance_type"],               # COMPLIANT or NON_COMPLIANT
                "Annotation": evaluation["annotation"],                        # Human-readable reason
                "OrderingTimestamp": configuration_item["configurationItemCaptureTime"]  # When resource was evaluated
            }
        ],
        ResultToken=event["resultToken"],  # Token provided by Config to track this evaluation
    )
    
    # Log the evaluation result for CloudWatch Logs
    print(evaluation["annotation"])
    
    return response
