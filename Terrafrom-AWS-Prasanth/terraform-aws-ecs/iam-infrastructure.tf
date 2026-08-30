########################################
# iam-infrastructure.tf
#
# The ECS infrastructure IAM role.
#
# This is the role ECS itself assumes to manage infrastructure on your behalf -
# reweighting ALB listener rules during a traffic shift, attaching EBS volumes
# at task launch, and registering VPC Lattice targets.
#
# It is what makes ECS-native BLUE_GREEN / LINEAR / CANARY work without
# CodeDeploy. advanced_configuration.role_arn is REQUIRED by the AWS provider,
# so a service using one of those strategies without this role fails at apply.
# The module creates it automatically rather than making that your problem.
#
# Supply service.deployment_configuration.ecs_alb_service_role_arn to use your
# own role instead, or set create_infrastructure_iam_role = false to require it.
#
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/infrastructure_IAM_role.html
########################################

data "aws_iam_policy_document" "infrastructure_iam_role" {
  count = length(local.services_needing_infrastructure_role) > 0 ? 1 : 0

  statement {
    sid     = "ECSServiceAssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "infrastructure" {
  for_each = local.services_needing_infrastructure_role

  name        = "${local.account_alias}-${each.key}-infra"
  description = "ECS infrastructure role for ${local.account_alias}-${each.key}"

  assume_role_policy    = data.aws_iam_policy_document.infrastructure_iam_role[0].json
  permissions_boundary  = var.infrastructure_iam_role_permissions_boundary
  force_detach_policies = true

  tags = merge(var.tags, { "Name" = "${local.account_alias}-${each.key}-infra" })
}

# Lets ECS shift traffic between the blue and green target groups by
# reweighting the production listener rule.
resource "aws_iam_role_policy_attachment" "infrastructure_load_balancer" {
  for_each = local.services_needing_lb_infrastructure_role

  role       = aws_iam_role.infrastructure[each.key].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers"
}

# Lets ECS create and attach EBS volumes at task launch.
resource "aws_iam_role_policy_attachment" "infrastructure_volumes" {
  for_each = local.services_needing_volume_infrastructure_role

  role       = aws_iam_role.infrastructure[each.key].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSInfrastructureRolePolicyForVolumes"
}

# Lets ECS register tasks as VPC Lattice targets.
resource "aws_iam_role_policy_attachment" "infrastructure_vpc_lattice" {
  for_each = local.services_needing_lattice_infrastructure_role

  role       = aws_iam_role.infrastructure[each.key].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonECSInfrastructureRolePolicyForVpcLattice"
}
