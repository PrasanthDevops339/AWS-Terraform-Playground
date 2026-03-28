package terraform.policies.aws_ebs_001_advise_encryption

import input as tfplan
import rego.v1

# Advisory-only policy: never block the plan.
default authz := true

# A plan is considered compliant when no advisory findings are produced.
compliant if {
	warn_count == 0
}

# Warn count can be used as a lightweight score for reporting.
warn_count := count(warn)
score := warn_count

# Advisory 1: Standalone EBS volume should be encrypted.
warn contains msg if {
	some resource in tfplan.resource_changes
	resource.type == "aws_ebs_volume"
	is_create_or_update(resource)
	not object.get(resource.change.after, "encrypted", false) == true
	msg := sprintf(
		"ADVISORY [EBS-ENC-001]: Standalone EBS volume '%s' is not encrypted. Set `encrypted = true` on aws_ebs_volume. [Address: %s]",
		[resource.name, resource.address],
	)
}

# Advisory 2: EC2 root volume should be encrypted when explicitly managed in the plan.
warn contains msg if {
	some resource in tfplan.resource_changes
	resource.type == "aws_instance"
	is_create_or_update(resource)
	some root in object.get(resource.change.after, "root_block_device", [])
	not object.get(root, "encrypted", false) == true
	msg := sprintf(
		"ADVISORY [EBS-ENC-002]: EC2 instance '%s' has an unencrypted root block device. Set `root_block_device.encrypted = true`. [Address: %s]",
		[resource.name, resource.address],
	)
}

# Advisory 3: Additional EBS volumes attached through aws_instance should be encrypted.
warn contains msg if {
	some resource in tfplan.resource_changes
	resource.type == "aws_instance"
	is_create_or_update(resource)
	some device in object.get(resource.change.after, "ebs_block_device", [])
	not object.get(device, "encrypted", false) == true
	msg := sprintf(
		"ADVISORY [EBS-ENC-003]: EC2 instance '%s' has an unencrypted attached EBS block device. Set `ebs_block_device.encrypted = true`. [Address: %s]",
		[resource.name, resource.address],
	)
}

# Structured findings for CI/reporting.
findings := [finding |
	some msg in warn
	finding := {
		"message": msg,
		"severity": "LOW",
		"enforcement": "advisory",
		"policy": "ebs-encryption-advisory",
	}
]

metadata := {
	"name": "ebs-encryption-advisory",
	"version": "2.1.0",
	"severity": "LOW",
	"enforcement": "advisory",
	"category": "encryption",
	"service": ["ec2", "ebs"],
	"description": "Advisory Terraform policy for standalone and EC2-attached EBS encryption.",
	"decision": "terraform/policies/aws_ebs_001_advise_encryption/authz",
}

# Helper: only evaluate create/update operations.
is_create_or_update(resource) if {
	"create" in resource.change.actions
}

is_create_or_update(resource) if {
	"update" in resource.change.actions
}
