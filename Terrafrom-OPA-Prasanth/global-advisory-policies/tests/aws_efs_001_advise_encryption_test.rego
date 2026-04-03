package terraform.policies.aws_efs_001_advise_encryption_test

import data.terraform.policies.aws_efs_001_advise_encryption as efs_advisory
import rego.v1

# authz is always true — advisory policy never blocks.
test_authz_is_always_true if {
    efs_advisory.authz with input as {"resource_changes": []}
}

# ---------------------------------------------------------------------------
# EFS-ENC-001: encryption not enabled
# ---------------------------------------------------------------------------
test_efs_unencrypted_generates_warn if {
    tfplan := {
        "resource_changes": [
            {
                "type": "aws_efs_file_system",
                "name": "main",
                "address": "aws_efs_file_system.main",
                "change": {
                    "actions": ["create"],
                    "after": {"encrypted": false},
                },
            },
        ],
    }

    some msg in efs_advisory.warn with input as tfplan
    contains(msg, "EFS-ENC-001")
}

# ---------------------------------------------------------------------------
# EFS-ENC-002: encrypted but no customer-managed KMS key
# ---------------------------------------------------------------------------
test_efs_encrypted_no_kms_generates_warn if {
    tfplan := {
        "resource_changes": [
            {
                "type": "aws_efs_file_system",
                "name": "main",
                "address": "aws_efs_file_system.main",
                "change": {
                    "actions": ["create"],
                    "after": {
                        "encrypted": true,
                        "kms_key_id": null,
                    },
                },
            },
        ],
    }

    some msg in efs_advisory.warn with input as tfplan
    contains(msg, "EFS-ENC-002")
}

test_efs_encrypted_empty_kms_generates_warn if {
    tfplan := {
        "resource_changes": [
            {
                "type": "aws_efs_file_system",
                "name": "main",
                "address": "aws_efs_file_system.main",
                "change": {
                    "actions": ["create"],
                    "after": {
                        "encrypted": true,
                        "kms_key_id": "",
                    },
                },
            },
        ],
    }

    some msg in efs_advisory.warn with input as tfplan
    contains(msg, "EFS-ENC-002")
}

# ---------------------------------------------------------------------------
# EFS-ENC-003: KMS key ID is not a valid ARN
# ---------------------------------------------------------------------------
test_efs_invalid_kms_arn_generates_warn if {
    tfplan := {
        "resource_changes": [
            {
                "type": "aws_efs_file_system",
                "name": "main",
                "address": "aws_efs_file_system.main",
                "change": {
                    "actions": ["create"],
                    "after": {
                        "encrypted": true,
                        "kms_key_id": "mrk-abc123",
                    },
                },
            },
        ],
    }

    some msg in efs_advisory.warn with input as tfplan
    contains(msg, "EFS-ENC-003")
}

# ---------------------------------------------------------------------------
# EFS-ENC-004: replication destination missing KMS key
# ---------------------------------------------------------------------------
test_efs_replication_no_kms_generates_warn if {
    tfplan := {
        "resource_changes": [
            {
                "type": "aws_efs_replication_configuration",
                "name": "dr",
                "address": "aws_efs_replication_configuration.dr",
                "change": {
                    "actions": ["create"],
                    "after": {
                        "destination": [{"region": "us-west-2", "kms_key_id": null}],
                    },
                },
            },
        ],
    }

    some msg in efs_advisory.warn with input as tfplan
    contains(msg, "EFS-ENC-004")
}

# ---------------------------------------------------------------------------
# Fully compliant: no warnings
# ---------------------------------------------------------------------------
test_compliant_efs_no_warn if {
    tfplan := {
        "resource_changes": [
            {
                "type": "aws_efs_file_system",
                "name": "main",
                "address": "aws_efs_file_system.main",
                "change": {
                    "actions": ["create"],
                    "after": {
                        "encrypted": true,
                        "kms_key_id": "arn:aws:kms:us-east-1:123456789012:key/mrk-abc123",
                    },
                },
            },
            {
                "type": "aws_efs_replication_configuration",
                "name": "dr",
                "address": "aws_efs_replication_configuration.dr",
                "change": {
                    "actions": ["create"],
                    "after": {
                        "destination": [{
                            "region": "us-west-2",
                            "kms_key_id": "arn:aws:kms:us-west-2:123456789012:key/mrk-def456",
                        }],
                    },
                },
            },
        ],
    }

    count(efs_advisory.warn with input as tfplan) == 0
    efs_advisory.compliant with input as tfplan
    efs_advisory.score with input as tfplan == 0
}

# ---------------------------------------------------------------------------
# Score and findings count match across all advisory codes
# ---------------------------------------------------------------------------
test_noncompliant_plan_score_matches_finding_count if {
    tfplan := {
        "resource_changes": [
            {
                "type": "aws_efs_file_system",
                "name": "no_enc",
                "address": "aws_efs_file_system.no_enc",
                "change": {
                    "actions": ["create"],
                    "after": {"encrypted": false},
                },
            },
            {
                "type": "aws_efs_file_system",
                "name": "no_kms",
                "address": "aws_efs_file_system.no_kms",
                "change": {
                    "actions": ["create"],
                    "after": {"encrypted": true, "kms_key_id": null},
                },
            },
            {
                "type": "aws_efs_replication_configuration",
                "name": "dr",
                "address": "aws_efs_replication_configuration.dr",
                "change": {
                    "actions": ["create"],
                    "after": {
                        "destination": [{"region": "us-west-2", "kms_key_id": ""}],
                    },
                },
            },
        ],
    }

    efs_advisory.score with input as tfplan == 3
    count(efs_advisory.findings with input as tfplan) == 3
}

# ---------------------------------------------------------------------------
# Module-sourced EFS should also be evaluated
# ---------------------------------------------------------------------------
test_module_efs_unencrypted_generates_warn if {
    tfplan := {
        "resource_changes": [
            {
                "type": "aws_efs_file_system",
                "name": "main",
                "address": "module.efs_storage.aws_efs_file_system.main",
                "module_address": "module.efs_storage",
                "change": {
                    "actions": ["create"],
                    "after": {"encrypted": false},
                },
            },
        ],
    }

    some msg in efs_advisory.warn with input as tfplan
    contains(msg, "EFS-ENC-001")
}

test_module_efs_compliant_no_warn if {
    tfplan := {
        "resource_changes": [
            {
                "type": "aws_efs_file_system",
                "name": "main",
                "address": "module.efs_storage.aws_efs_file_system.main",
                "module_address": "module.efs_storage",
                "change": {
                    "actions": ["create"],
                    "after": {
                        "encrypted": true,
                        "kms_key_id": "arn:aws:kms:us-east-2:590183660495:key/mrk-2982d8681bffb4",
                    },
                },
            },
        ],
    }

    count(efs_advisory.warn with input as tfplan) == 0
}
