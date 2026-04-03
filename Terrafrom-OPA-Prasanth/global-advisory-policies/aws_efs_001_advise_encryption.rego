import data.terraform.utils.advise_module_usage.library
import input as tfplan
import rego.v1

# Advisory-only policy: never block the plan.
default authz := true

# Resource types this policy evaluates.
resource_types := {"aws_efs_file_system", "aws_efs_replication_configuration"}

# A plan is considered compliant when no advisory findings are produced.
compliant if {
    warn_count == 0
}

# Warn count can be used as a lightweight score for reporting.
warn_count := count(warn)
score := warn_count

# List all resources of a supported type.
resources[resource_type] := matched if {
    some resource_type in resource_types
    matched := [resource |
        some resource in tfplan.resource_changes
        resource.type == resource_type
    ]
}

# EFS file systems being created or updated.
efs_file_system_changes contains resource if {
    some resource in resources.aws_efs_file_system
    is_create_or_update(resource)
}

# EFS replication configurations being created or updated.
efs_replication_changes contains resource if {
    some resource in resources.aws_efs_replication_configuration
    is_create_or_update(resource)
}

# Advisory 1: EFS file system should have encryption enabled.
warn contains msg if {
    some resource in efs_file_system_changes
    not value_is_true(resource.change.after.encrypted)
    msg := sprintf(
        "ADVISORY [EFS-ENC-001]: EFS file system '%s' does not have encryption enabled. Set `encrypted = true` on aws_efs_file_system. [Address: %s]",
        [resource.name, resource.address],
    )
}

# Advisory 2: EFS file system should use a customer-managed KMS key.
warn contains msg if {
    some resource in efs_file_system_changes
    value_is_true(resource.change.after.encrypted)
    not _has_kms_key(resource.change.after)
    msg := sprintf(
        "ADVISORY [EFS-ENC-002]: EFS file system '%s' is encrypted but missing a customer-managed KMS key. Set `kms_key_id` to a CMK ARN — the AWS-managed default key does not support custom key policies or cross-account access. [Address: %s]",
        [resource.name, resource.address],
    )
}

# Advisory 3: EFS KMS key ID should be a valid ARN.
warn contains msg if {
    some resource in efs_file_system_changes
    value_is_true(resource.change.after.encrypted)
    _has_kms_key(resource.change.after)
    kms_key := resource.change.after.kms_key_id
    not startswith(kms_key, "arn:aws:kms:")
    msg := sprintf(
        "ADVISORY [EFS-ENC-003]: EFS file system '%s' has kms_key_id '%s' which is not a valid KMS ARN. Expected format: arn:aws:kms:<region>:<account-id>:key/<key-id>. [Address: %s]",
        [resource.name, kms_key, resource.address],
    )
}

# Advisory 4: EFS replication destination should use a customer-managed KMS key.
warn contains msg if {
    some resource in efs_replication_changes
    some dest in object.get(resource.change.after, "destination", [])
    not _has_kms_key(dest)
    msg := sprintf(
        "ADVISORY [EFS-ENC-004]: EFS replication configuration '%s' has a destination without a customer-managed KMS key. Set `kms_key_id` on every replication destination block. [Address: %s]",
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
        "policy": "efs-encryption-advisory",
    }
]

metadata := {
    "name": "efs-encryption-advisory",
    "version": "1.0.0",
    "severity": "LOW",
    "enforcement": "advisory",
    "category": "encryption",
    "service": ["efs"],
    "description": "Advisory Terraform policy for EFS at-rest encryption and customer-managed KMS key usage.",
    "decision": "terraform/policies/aws_efs_001_advise_encryption/authz",
}

# Helper: only evaluate create/update operations.
is_create_or_update(resource) if {
    "create" in resource.change.actions
}

is_create_or_update(resource) if {
    "update" in resource.change.actions
}

# Helper: returns true only when Terraform explicitly sets the value to true.
value_is_true(value) if {
    value == true
}

# Helper: object has a non-null, non-empty kms_key_id.
_has_kms_key(obj) if {
    kms_key := obj.kms_key_id
    kms_key != null
    kms_key != ""
}
