# ============================================================================
# OPA Policy: EFS KMS Encryption at Rest Enforcement
# ============================================================================
# Scope:       aws_efs_file_system resources in Terraform plan JSON
# Enforces:    (1) encrypted = true
#              (2) kms_key_id is set and non-empty (customer-managed KMS key)
#              (3) kms_key_id uses valid ARN format
#              (4) Replication destinations also use KMS encryption
# Integration: terraform show -json → opa eval → GitLab CI gate
# Reference:   https://www.openpolicyagent.org/docs/terraform
# ============================================================================

package terraform.policies.aws_efs_001_mandatory_encryption

import rego.v1

# ---------------------------------------------------------------------------
# Helpers: Extract EFS resources from plan
# ---------------------------------------------------------------------------

# All EFS file system resources being created or updated
efs_file_systems contains resource if {
	some resource in input.resource_changes
	resource.type == "aws_efs_file_system"
	resource.change.actions[_] in {"create", "update"}
}

# All EFS replication configuration resources being created or updated
efs_replication_configs contains resource if {
	some resource in input.resource_changes
	resource.type == "aws_efs_replication_configuration"
	resource.change.actions[_] in {"create", "update"}
}

# ---------------------------------------------------------------------------
# Rule 1: EFS must have encryption enabled
# ---------------------------------------------------------------------------
deny contains msg if {
	some resource in efs_file_systems
	not resource.change.after.encrypted
	msg := sprintf(
		"DENY [EFS-ENC-001]: EFS '%s' does not have encryption enabled. Set `encrypted = true` in the aws_efs_file_system resource. [Address: %s]",
		[resource.name, resource.address],
	)
}

# ---------------------------------------------------------------------------
# Rule 2: EFS must use a customer-managed KMS key (not AWS default)
# ---------------------------------------------------------------------------
deny contains msg if {
	some resource in efs_file_systems
	resource.change.after.encrypted == true
	not _has_kms_key(resource.change.after)
	msg := sprintf(
		"DENY [EFS-ENC-002]: EFS '%s' is encrypted but missing a customer-managed KMS key. Set `kms_key_id = var.kms_key_arn` pointing to a customer-managed CMK. AWS-managed default key (aws/elasticfilesystem) does not allow cross-account access or custom key policy. [Address: %s]",
		[resource.name, resource.address],
	)
}

# ---------------------------------------------------------------------------
# Rule 3: KMS key ARN format validation
# ---------------------------------------------------------------------------
deny contains msg if {
	some resource in efs_file_systems
	resource.change.after.encrypted == true
	_has_kms_key(resource.change.after)
	kms_key := resource.change.after.kms_key_id
	not startswith(kms_key, "arn:aws:kms:")
	msg := sprintf(
		"DENY [EFS-ENC-003]: EFS '%s' has kms_key_id '%s' which is not a valid KMS ARN. Expected format: arn:aws:kms:<region>:<account-id>:key/<key-id>. [Address: %s]",
		[resource.name, kms_key, resource.address],
	)
}

# ---------------------------------------------------------------------------
# Rule 4: Replication destination must also use KMS encryption
# ---------------------------------------------------------------------------
deny contains msg if {
	some resource in efs_replication_configs
	some dest in resource.change.after.destination
	not _has_kms_key(dest)
	msg := sprintf(
		"DENY [EFS-ENC-004]: EFS replication configuration '%s' has a destination without a customer-managed KMS key. Set `kms_key_id` on every replication destination block. [Address: %s]",
		[resource.name, resource.address],
	)
}

# ---------------------------------------------------------------------------
# Helper: Check if object has a non-null, non-empty kms_key_id
# ---------------------------------------------------------------------------
_has_kms_key(obj) if {
	kms_key := obj.kms_key_id
	kms_key != null
	kms_key != ""
}

# ---------------------------------------------------------------------------
# Compliance summary (consumed by CI/CD and reporting)
# ---------------------------------------------------------------------------
violation_count := count(deny)

compliant if {
	violation_count == 0
}

# Structured violations for JSON reporting
violations := [v |
	some msg in deny
	v := {"message": msg, "severity": "HIGH"}
]

# ---------------------------------------------------------------------------
# Policy metadata
# ---------------------------------------------------------------------------
metadata := {
	"name": "efs-kms-encryption-at-rest",
	"version": "1.0.0",
	"severity": "HIGH",
	"enforcement": "mandatory",
	"category": "encryption",
	"service": "efs",
	"framework": ["CIS AWS 2.4.1", "AWS Well-Architected SEC08-BP02"],
	"description": "Enforces customer-managed KMS encryption at rest for all EFS file systems and replication destinations",
}
