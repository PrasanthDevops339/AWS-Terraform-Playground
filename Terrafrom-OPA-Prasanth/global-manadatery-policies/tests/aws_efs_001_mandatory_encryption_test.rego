# ============================================================================
# OPA Tests: EFS KMS Encryption at Rest Policy
# ============================================================================
# Run:  opa test . -v
# ============================================================================

package terraform.policies.aws_efs_001_mandatory_encryption_test

import rego.v1

import data.terraform.policies.aws_efs_001_mandatory_encryption as encryption

# ============================= TEST FIXTURES ================================

# --- COMPLIANT: encrypted + customer-managed KMS key ---
mock_compliant := {
	"resource_changes": [
		{
			"address": "module.efs.aws_efs_file_system.main",
			"type": "aws_efs_file_system",
			"name": "main",
			"change": {
				"actions": ["create"],
				"after": {
					"encrypted": true,
					"kms_key_id": "arn:aws:kms:us-east-1:123456789012:key/abcd-1234-efgh-5678",
					"performance_mode": "generalPurpose",
					"throughput_mode": "bursting",
					"creation_token": "app-efs",
					"tags": {"Name": "dev-app-efs", "ManagedBy": "terraform"},
				},
			},
		},
		{
			"address": "module.efs.aws_efs_replication_configuration.main[0]",
			"type": "aws_efs_replication_configuration",
			"name": "main",
			"change": {
				"actions": ["create"],
				"after": {
					"destination": [{
						"kms_key_id": "arn:aws:kms:us-west-2:123456789012:key/wxyz-9876",
						"region": "us-west-2",
					}],
				},
			},
		},
	],
}

# --- NON-COMPLIANT: encrypted = false ---
mock_not_encrypted := {
	"resource_changes": [{
		"address": "module.efs.aws_efs_file_system.main",
		"type": "aws_efs_file_system",
		"name": "main",
		"change": {
			"actions": ["create"],
			"after": {
				"encrypted": false,
				"kms_key_id": null,
			},
		},
	}],
}

# --- NON-COMPLIANT: encrypted but kms_key_id = null (AWS default key) ---
mock_no_kms_key := {
	"resource_changes": [{
		"address": "module.efs.aws_efs_file_system.main",
		"type": "aws_efs_file_system",
		"name": "main",
		"change": {
			"actions": ["create"],
			"after": {
				"encrypted": true,
				"kms_key_id": null,
			},
		},
	}],
}

# --- NON-COMPLIANT: encrypted but kms_key_id = "" (empty string) ---
mock_empty_kms := {
	"resource_changes": [{
		"address": "module.efs.aws_efs_file_system.main",
		"type": "aws_efs_file_system",
		"name": "main",
		"change": {
			"actions": ["create"],
			"after": {
				"encrypted": true,
				"kms_key_id": "",
			},
		},
	}],
}

# --- NON-COMPLIANT: encrypted but invalid ARN format ---
mock_bad_arn := {
	"resource_changes": [{
		"address": "module.efs.aws_efs_file_system.main",
		"type": "aws_efs_file_system",
		"name": "main",
		"change": {
			"actions": ["create"],
			"after": {
				"encrypted": true,
				"kms_key_id": "alias/my-efs-key",
			},
		},
	}],
}

# --- NON-COMPLIANT: replication destination missing KMS ---
mock_repl_no_kms := {
	"resource_changes": [
		{
			"address": "module.efs.aws_efs_file_system.main",
			"type": "aws_efs_file_system",
			"name": "main",
			"change": {
				"actions": ["create"],
				"after": {
					"encrypted": true,
					"kms_key_id": "arn:aws:kms:us-east-1:123456789012:key/abcd-1234",
				},
			},
		},
		{
			"address": "module.efs.aws_efs_replication_configuration.main[0]",
			"type": "aws_efs_replication_configuration",
			"name": "main",
			"change": {
				"actions": ["create"],
				"after": {
					"destination": [{
						"kms_key_id": null,
						"region": "us-west-2",
					}],
				},
			},
		},
	],
}

# --- EDGE: delete action should NOT be evaluated ---
mock_delete := {
	"resource_changes": [{
		"address": "module.efs.aws_efs_file_system.main",
		"type": "aws_efs_file_system",
		"name": "main",
		"change": {
			"actions": ["delete"],
			"before": {"encrypted": false, "kms_key_id": null},
			"after": null,
		},
	}],
}

# --- EDGE: no-op / read should NOT be evaluated ---
mock_noop := {
	"resource_changes": [{
		"address": "module.efs.aws_efs_file_system.main",
		"type": "aws_efs_file_system",
		"name": "main",
		"change": {
			"actions": ["no-op"],
			"before": {"encrypted": true, "kms_key_id": "arn:aws:kms:us-east-1:123456789012:key/abcd"},
			"after": {"encrypted": true, "kms_key_id": "arn:aws:kms:us-east-1:123456789012:key/abcd"},
		},
	}],
}

# --- EDGE: plan with no EFS at all ---
mock_no_efs := {
	"resource_changes": [{
		"address": "aws_s3_bucket.logs",
		"type": "aws_s3_bucket",
		"name": "logs",
		"change": {
			"actions": ["create"],
			"after": {"bucket": "my-logs-bucket"},
		},
	}],
}

# --- MIXED: one compliant EFS + one non-compliant EFS ---
mock_mixed := {
	"resource_changes": [
		{
			"address": "module.efs_good.aws_efs_file_system.main",
			"type": "aws_efs_file_system",
			"name": "main",
			"change": {
				"actions": ["create"],
				"after": {
					"encrypted": true,
					"kms_key_id": "arn:aws:kms:us-east-1:123456789012:key/good-key",
				},
			},
		},
		{
			"address": "module.efs_bad.aws_efs_file_system.main",
			"type": "aws_efs_file_system",
			"name": "main",
			"change": {
				"actions": ["create"],
				"after": {
					"encrypted": false,
					"kms_key_id": null,
				},
			},
		},
	],
}

# ================================ TESTS =====================================

# ---------- Rule 1: encrypted = true ----------

test_compliant_efs_passes if {
	count(encryption.deny) == 0 with input as mock_compliant
}

test_compliant_efs_is_compliant if {
	encryption.compliant with input as mock_compliant
}

test_unencrypted_efs_denied if {
	count(encryption.deny) > 0 with input as mock_not_encrypted
}

test_unencrypted_efs_has_correct_code if {
	some msg in encryption.deny with input as mock_not_encrypted
	contains(msg, "EFS-ENC-001")
}

# ---------- Rule 2: kms_key_id present ----------

test_null_kms_key_denied if {
	count(encryption.deny) > 0 with input as mock_no_kms_key
}

test_null_kms_key_has_correct_code if {
	some msg in encryption.deny with input as mock_no_kms_key
	contains(msg, "EFS-ENC-002")
}

test_empty_kms_key_denied if {
	count(encryption.deny) > 0 with input as mock_empty_kms
}

test_empty_kms_key_has_correct_code if {
	some msg in encryption.deny with input as mock_empty_kms
	contains(msg, "EFS-ENC-002")
}

# ---------- Rule 3: KMS ARN format ----------

test_bad_arn_denied if {
	count(encryption.deny) > 0 with input as mock_bad_arn
}

test_bad_arn_has_correct_code if {
	some msg in encryption.deny with input as mock_bad_arn
	contains(msg, "EFS-ENC-003")
}

# ---------- Rule 4: Replication KMS ----------

test_replication_no_kms_denied if {
	count(encryption.deny) > 0 with input as mock_repl_no_kms
}

test_replication_no_kms_has_correct_code if {
	some msg in encryption.deny with input as mock_repl_no_kms
	contains(msg, "EFS-ENC-004")
}

test_replication_with_kms_passes if {
	# mock_compliant includes a compliant replication config
	not encryption.deny[_] with input as mock_compliant
}

# ---------- Edge cases ----------

test_delete_action_ignored if {
	count(encryption.deny) == 0 with input as mock_delete
}

test_noop_action_ignored if {
	count(encryption.deny) == 0 with input as mock_noop
}

test_no_efs_resources_passes if {
	count(encryption.deny) == 0 with input as mock_no_efs
}

test_no_efs_is_compliant if {
	encryption.compliant with input as mock_no_efs
}

# ---------- Mixed plan ----------

test_mixed_plan_has_one_denial if {
	count(encryption.deny) == 1 with input as mock_mixed
}

test_mixed_plan_targets_bad_resource if {
	some msg in encryption.deny with input as mock_mixed
	contains(msg, "efs_bad")
}

# ---------- Metadata ----------

test_metadata_exists if {
	encryption.metadata.name == "efs-kms-encryption-at-rest"
}

test_metadata_severity_high if {
	encryption.metadata.severity == "HIGH"
}

test_metadata_enforcement_mandatory if {
	encryption.metadata.enforcement == "mandatory"
}
