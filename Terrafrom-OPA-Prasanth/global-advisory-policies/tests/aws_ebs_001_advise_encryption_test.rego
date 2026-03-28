package terraform.policies.aws_ebs_001_advise_encryption_test

import data.terraform.policies.aws_ebs_001_advise_encryption
import rego.v1

test_authz_is_true_for_advisory_policy if {
	aws_ebs_001_advise_encryption.authz with input as {"resource_changes": []}
}

test_standalone_ebs_unencrypted_generates_warn if {
	tfplan := {
		"resource_changes": [
			{
				"type": "aws_ebs_volume",
				"name": "data_disk",
				"address": "aws_ebs_volume.data_disk",
				"change": {
					"actions": ["create"],
					"after": {"encrypted": false},
				},
			},
		],
	}

	some msg in aws_ebs_001_advise_encryption.warn with input as tfplan
	contains(msg, "EBS-ENC-001")
}

test_ec2_root_volume_unencrypted_generates_warn if {
	tfplan := {
		"resource_changes": [
			{
				"type": "aws_instance",
				"name": "app",
				"address": "aws_instance.app",
				"change": {
					"actions": ["create"],
					"after": {
						"root_block_device": [{"encrypted": false}],
					},
				},
			},
		],
	}

	some msg in aws_ebs_001_advise_encryption.warn with input as tfplan
	contains(msg, "EBS-ENC-002")
}

test_ec2_attached_ebs_unencrypted_generates_warn if {
	tfplan := {
		"resource_changes": [
			{
				"type": "aws_instance",
				"name": "app",
				"address": "aws_instance.app",
				"change": {
					"actions": ["update"],
					"after": {
						"ebs_block_device": [{"encrypted": false}],
					},
				},
			},
		],
	}

	some msg in aws_ebs_001_advise_encryption.warn with input as tfplan
	contains(msg, "EBS-ENC-003")
}

test_compliant_resources_have_no_warn if {
	tfplan := {
		"resource_changes": [
			{
				"type": "aws_ebs_volume",
				"name": "data_disk",
				"address": "aws_ebs_volume.data_disk",
				"change": {
					"actions": ["create"],
					"after": {"encrypted": true},
				},
			},
			{
				"type": "aws_instance",
				"name": "app",
				"address": "aws_instance.app",
				"change": {
					"actions": ["create"],
					"after": {
						"root_block_device": [{"encrypted": true}],
						"ebs_block_device": [{"encrypted": true}],
					},
				},
			},
		],
	}

	count(aws_ebs_001_advise_encryption.warn with input as tfplan) == 0
	aws_ebs_001_advise_encryption.compliant with input as tfplan
	aws_ebs_001_advise_encryption.score with input as tfplan == 0
}

test_noncompliant_plan_score_matches_finding_count if {
	tfplan := {
		"resource_changes": [
			{
				"type": "aws_ebs_volume",
				"name": "data_disk",
				"address": "aws_ebs_volume.data_disk",
				"change": {
					"actions": ["create"],
					"after": {"encrypted": false},
				},
			},
			{
				"type": "aws_instance",
				"name": "app",
				"address": "aws_instance.app",
				"change": {
					"actions": ["create"],
					"after": {
						"root_block_device": [{"encrypted": false}],
						"ebs_block_device": [{"encrypted": false}],
					},
				},
			},
		],
	}

	aws_ebs_001_advise_encryption.score with input as tfplan == 3
	count(aws_ebs_001_advise_encryption.findings with input as tfplan) == 3
}

# EC2 from a module should be checked for both root_block_device and ebs_block_device.
test_module_ec2_unencrypted_root_and_ebs_generates_warn if {
	tfplan := {
		"resource_changes": [
			{
				"type": "aws_instance",
				"name": "main",
				"address": "module.ec2_role.aws_instance.main",
				"module_address": "module.ec2_role",
				"change": {
					"actions": ["create"],
					"after": {
						"root_block_device": [
							{
								"delete_on_termination": true,
								"encrypted": false,
								"volume_size": 80,
								"volume_type": "gp3",
								"throughput": 200,
							},
						],
						"ebs_block_device": [
							{
								"delete_on_termination": true,
								"device_name": "/dev/sdf",
								"encrypted": false,
								"volume_size": 10,
								"volume_type": "gp3",
								"throughput": 200,
							},
						],
					},
				},
			},
		],
	}

	warns := aws_ebs_001_advise_encryption.warn with input as tfplan
	count(warns) == 2
	some msg_root in warns
	contains(msg_root, "EBS-ENC-002")
	some msg_ebs in warns
	contains(msg_ebs, "EBS-ENC-003")
}

# EC2 from a module with encrypted root and ebs block devices should pass.
test_module_ec2_encrypted_root_and_ebs_no_warn if {
	tfplan := {
		"resource_changes": [
			{
				"type": "aws_instance",
				"name": "main",
				"address": "module.ec2_role.aws_instance.main",
				"module_address": "module.ec2_role",
				"change": {
					"actions": ["create"],
					"after": {
						"root_block_device": [
							{
								"delete_on_termination": true,
								"encrypted": true,
								"volume_size": 80,
								"volume_type": "gp3",
								"kms_key_id": "arn:aws:kms:us-east-2:590183660495:key/mrk-2982d",
							},
						],
						"ebs_block_device": [
							{
								"delete_on_termination": true,
								"device_name": "/dev/sdf",
								"encrypted": true,
								"volume_size": 10,
								"volume_type": "gp3",
								"kms_key_id": "arn:aws:kms:us-east-2:590183660495:key/mrk-2982d8681bffb4",
							},
						],
					},
				},
			},
		],
	}

	count(aws_ebs_001_advise_encryption.warn with input as tfplan) == 0
}
