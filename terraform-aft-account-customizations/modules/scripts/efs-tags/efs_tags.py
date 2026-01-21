
import json
import boto3

jsonfile = open('efs_tags.json', 'r')
jsondat = jsonfile.read()

obj = json.loads(jsondat)
print(obj['required_tags'])


def evaluate_compliance(configuration_item, rule_parameters):
    required_tags = rule_parameters.get("required_tags", {})
    resource_tags = configuration_item.get("tags", {}) or {}

    non_compliant_tags = []
    approved_tag_keys = []
    missing_tag_keys = []

    for tag_name, accepted_values in required_tags.items():
        approved_tag_keys.append(tag_name)

    for x in approved_tag_keys:
        if x not in resource_tags:
            missing_tag_keys.append(x)

    if missing_tag_keys:
        return {
            "compliance_type": "NON_COMPLIANT",
            "annotation": f"Required EFS tag keys are missing: {', '.join(missing_tag_keys)}"
        }

    for tag_name, accepted_values in required_tags.items():
        # Skip validation if accepted_values is empty (any value allowed)
        if not accepted_values:
            continue
            
        if tag_name in resource_tags and resource_tags[tag_name] not in accepted_values:
            non_compliant_tags.append(f"{tag_name}={resource_tags[tag_name]}")

    if non_compliant_tags:
        return {
            "compliance_type": "NON_COMPLIANT",
            "annotation": f"EFS tag values do not match accepted values: {', '.join(non_compliant_tags)}"
        }

    return {
        "compliance_type": "COMPLIANT",
        "annotation": "All required EFS tags have values matching accepted values."
    }


def lambda_handler(event, context):
    print(event)
    invoking_event = json.loads(event["invokingEvent"])
    configuration_item = invoking_event["configurationItem"]
    rule_parameters = json.loads(jsondat)

    evaluation = evaluate_compliance(configuration_item, rule_parameters)

    config = boto3.client("config")
    response = config.put_evaluations(
        Evaluations=[
            {
                "ComplianceResourceType": configuration_item["resourceType"],
                "ComplianceResourceId": configuration_item["resourceId"],
                "ComplianceType": evaluation["compliance_type"],
                "Annotation": evaluation["annotation"],
                "OrderingTimestamp": configuration_item["configurationItemCaptureTime"]
            }
        ],
        ResultToken=event["resultToken"],
    )
    print(evaluation["annotation"])
    return response
