data "aws_iam_account_alias" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

# Current ECS-optimized AMI per EC2 capacity provider. Resolved from SSM so
# amd64, arm64 and Bottlerocket variants can coexist in one cluster.
data "aws_ssm_parameter" "ecs_ami" {
  for_each = local.ec2_capacity_providers_needing_ami

  name = each.value.ami_ssm_parameter
}
