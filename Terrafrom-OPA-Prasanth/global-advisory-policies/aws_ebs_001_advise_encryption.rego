import data.terraform.utils.advise_module_usage.library
import input as tfplan

# Advisory-only policy: never block the plan.
default authz = true

# Resource types this policy evaluates.
resource_types := {"aws_ebs_volume", "aws_instance"}

# A plan is considered compliant when no advisory findings are produced.
<<<<<<< HEAD
compliant if {
    warn_count == 0
=======
compliant {
	warn_count == 0
>>>>>>> refs/remotes/origin/feature/ami-management-policy
}

# Warn count can be used as a lightweight score for reporting.
warn_count = count(warn)
score = warn_count

# List all resources of a supported type.
resources[resource_type] := matched if {
    some resource_type in resource_types
    matched := [resource |
        some resource in tfplan.resource_changes
        resource.type == resource_type
    ]
}

# Standalone EBS volumes being created or updated.
ebs_volume_changes contains resource if {
    some resource in resources.aws_ebs_volume
    is_create_or_update(resource)
}

# EC2 instances being created or updated.
ec2_instance_changes contains resource if {
    some resource in resources.aws_instance
    is_create_or_update(resource)
}

# Advisory 1: Standalone EBS volume should be encrypted.
<<<<<<< HEAD
warn contains msg if {
    some resource in ebs_volume_changes
    not value_is_true(resource.change.after.encrypted)
    msg := sprintf(
        "ADVISORY [EBS-ENC-001]: Standalone EBS volume '%s' is not encrypted. Set `encrypted = true` on aws_ebs_volume. [Address: %s]",
        [resource.name, resource.address],
    )
}

# Advisory 2: EC2 root volume should be encrypted when explicitly managed in the plan.
warn contains msg if {
    some resource in ec2_instance_changes
    some root in object.get(resource.change.after, "root_block_device", [])
    not value_is_true(root.encrypted)
    msg := sprintf(
        "ADVISORY [EBS-ENC-002]: EC2 instance '%s' has an unencrypted root block device. Set `root_block_device.encrypted = true`. [Address: %s]",
        [resource.name, resource.address],
    )
}

# Advisory 3: Additional EBS volumes attached through aws_instance should be encrypted.
warn contains msg if {
    some resource in ec2_instance_changes
    some device in object.get(resource.change.after, "ebs_block_device", [])
    not value_is_true(device.encrypted)
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
    "version": "2.0.0",
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
=======
warn[msg] {
	resource := tfplan.resource_changes[_]
	resource.type == "aws_ebs_volume"
	is_create_or_update(resource)
	encrypted := object.get(resource.change.after, "encrypted", false)
	encrypted != true
	msg := sprintf(
		"ADVISORY [EBS-ENC-001]: Standalone EBS volume '%s' is not encrypted. Set `encrypted = true` on aws_ebs_volume. [Address: %s]",
		[resource.name, resource.address],
	)
}

# Advisory 2: EC2 root volume should be encrypted when explicitly managed in the plan.
warn[msg] {
	resource := tfplan.resource_changes[_]
	resource.type == "aws_instance"
	is_create_or_update(resource)
	root := object.get(resource.change.after, "root_block_device", [])[_]
	encrypted := object.get(root, "encrypted", false)
	encrypted != true
	msg := sprintf(
		"ADVISORY [EBS-ENC-002]: EC2 instance '%s' has an unencrypted root block device. Set `root_block_device.encrypted = true`. [Address: %s]",
		[resource.name, resource.address],
	)
}

# Advisory 3: Additional EBS volumes attached through aws_instance should be encrypted.
warn[msg] {
	resource := tfplan.resource_changes[_]
	resource.type == "aws_instance"
	is_create_or_update(resource)
	device := object.get(resource.change.after, "ebs_block_device", [])[_]
	encrypted := object.get(device, "encrypted", false)
	encrypted != true
	msg := sprintf(
		"ADVISORY [EBS-ENC-003]: EC2 instance '%s' has an unencrypted attached EBS block device. Set `ebs_block_device.encrypted = true`. [Address: %s]",
		[resource.name, resource.address],
	)
}

# Structured findings for CI/reporting.
findings = [finding |
	msg := warn[_]
	finding := {
		"message": msg,
		"severity": "LOW",
		"enforcement": "advisory",
		"policy": "ebs-encryption-advisory",
	}
]

metadata = {
	"name": "ebs-encryption-advisory",
	"version": "2.2.0",
	"severity": "LOW",
	"enforcement": "advisory",
	"category": "encryption",
	"service": ["ec2", "ebs"],
	"description": "Advisory Terraform policy for standalone and EC2-attached EBS encryption.",
	"decision": "terraform/policies/aws_ebs_001_advise_encryption/authz",
}

# Helper: only evaluate create/update operations.
is_create_or_update(resource) {
	resource.change.actions[_] == "create"
}

is_create_or_update(resource) {
	resource.change.actions[_] == "update"
>>>>>>> refs/remotes/origin/feature/ami-management-policy
}

# Helper: returns true only when Terraform explicitly sets the value to true.
value_is_true(value) if {
    value == true
}