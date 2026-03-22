package terraform.analysis_test

import data.terraform.analysis
import rego.v1

test_authz_is_true_for_advisory_policy if {
	analysis.authz with input as {"resource_changes": []}
}

test_standalone_ebs_unencrypted_generates_advice if {
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

	some msg in analysis.advice with input as tfplan
	contains(msg, "EBS-ENC-001")
}

test_ec2_root_volume_unencrypted_generates_advice if {
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

	some msg in analysis.advice with input as tfplan
	contains(msg, "EBS-ENC-002")
}

test_ec2_attached_ebs_unencrypted_generates_advice if {
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

	some msg in analysis.advice with input as tfplan
	contains(msg, "EBS-ENC-003")
}

test_compliant_resources_have_no_advice if {
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

	count(analysis.advice with input as tfplan) == 0
	analysis.compliant with input as tfplan
	analysis.score with input as tfplan == 0
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

	analysis.score with input as tfplan == 3
	count(analysis.findings with input as tfplan) == 3
}
