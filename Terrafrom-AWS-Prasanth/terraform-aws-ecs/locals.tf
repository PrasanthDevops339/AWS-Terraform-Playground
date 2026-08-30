########################################
# locals.tf
#
# Central derivation for the module. Everything that used to be decided inline
# in a resource - launch type, network mode, which deployment controller owns a
# service - is resolved once here, so each rule has a single home and the
# resource files stay readable.
########################################

locals {
  account_alias = data.aws_iam_account_alias.current.account_alias
  partition     = data.aws_partition.current.partition
  region        = data.aws_region.current.region
  account_id    = data.aws_caller_identity.current.account_id

  cluster_name_full = "${local.account_alias}-${var.cluster_name}"

  # Services must be able to reference an existing cluster too. Without this,
  # create_cluster = false left every service pointing at a cluster resource
  # with zero instances.
  cluster_id = var.create_cluster ? aws_ecs_cluster.main[0].id : var.existing_cluster_arn

  ##############################################################################
  # EC2 capacity providers
  ##############################################################################

  # Capacity provider name as ECS sees it.
  ec2_capacity_provider_names = {
    for k, cp in var.ec2_capacity_providers : k => "${local.account_alias}-${var.cluster_name}-${k}"
  }

  ec2_capacity_providers_needing_ami = {
    for k, cp in var.ec2_capacity_providers : k => cp if cp.ami_id == null
  }

  # A plain launch-template ASG, versus one with a mixed instances policy for
  # Spot diversification. The two cannot be expressed in one resource.
  ec2_capacity_providers_single = {
    for k, cp in var.ec2_capacity_providers : k => cp if length(cp.instance_types_override) == 0
  }

  ec2_capacity_providers_mixed = {
    for k, cp in var.ec2_capacity_providers : k => cp if length(cp.instance_types_override) > 0
  }

  ec2_capacity_provider_sgs = {
    for k, cp in var.ec2_capacity_providers : k => cp if cp.create_security_group
  }

  ec2_instance_ingress_rules = merge([
    for k, cp in var.ec2_capacity_providers : {
      for idx, rule in cp.security_group_ingress_rules :
      "${k}-${idx}" => merge(rule, { cp_key = k })
    } if cp.create_security_group
  ]...)

  ec2_instance_egress_rules = merge([
    for k, cp in var.ec2_capacity_providers : {
      for idx, rule in cp.security_group_egress_rules :
      "${k}-${idx}" => merge(rule, { cp_key = k })
    } if cp.create_security_group
  ]...)

  # Fargate providers named in the variable, plus every EC2 provider this module
  # creates. A provider must be associated with the cluster before any service
  # can reference it in a capacity provider strategy.
  all_capacity_providers = concat(
    var.capacity_providers,
    values(local.ec2_capacity_provider_names),
  )

  ##############################################################################
  # Per-service derivation
  #
  # container_config is intentionally `any` to stay backwards compatible, so
  # every read goes through try() with a documented default.
  ##############################################################################

  svc = {
    for k, v in var.container_config : k => {
      # FARGATE | EC2 | EXTERNAL. Defaults to the module-wide default, which
      # itself defaults to FARGATE - so existing callers are unaffected.
      launch_type = try(v.service.launch_type, var.launch_type_default)

      capacity_provider_strategy = try(v.service.capacity_provider_strategy, [])

      # ECS | EXTERNAL
      deployment_controller = try(v.service.deployment_controller.type, "ECS")

      deployment_strategy = try(
        v.service.deployment_configuration.strategy,
        var.deployment_strategy_default,
      )

      scheduling_strategy = try(v.service.scheduling_strategy, "REPLICA")
    }
  }

  # Second pass: values that depend on the first pass.
  svc_resolved = {
    for k, v in var.container_config : k => merge(local.svc[k], {
      # awsvpc is mandatory on Fargate; EC2 defaults to bridge but may be any
      # of awsvpc / bridge / host / none.
      network_mode = try(
        v.task_definition.network_mode,
        local.svc[k].launch_type == "FARGATE" ? "awsvpc" : "bridge",
      )

      requires_compatibilities = try(
        v.task_definition.requires_compatibilities,
        [local.svc[k].launch_type],
      )

      # launch_type and capacity_provider_strategy are mutually exclusive in the
      # ECS API. When a strategy is supplied the launch_type argument is dropped.
      effective_launch_type = (
        length(local.svc[k].capacity_provider_strategy) > 0 ? null : local.svc[k].launch_type
      )

      # platform_version is Fargate-only and is rejected on EC2.
      platform_version = (
        local.svc[k].launch_type == "FARGATE"
        ? try(v.service.platform_version, "LATEST")
        : null
      )

      is_daemon         = local.svc[k].scheduling_strategy == "DAEMON"
      is_ecs_controller = local.svc[k].deployment_controller == "ECS"

      # Traffic-shifting strategies, as opposed to an in-place rolling update.
      shifts_traffic = (
        local.svc[k].deployment_controller == "ECS" &&
        local.svc[k].deployment_strategy != "ROLLING"
      )
    })
  }

  ##############################################################################
  # Service groupings by deployment controller
  #
  # Each controller gets its own aws_ecs_service resource because
  # lifecycle.ignore_changes cannot be computed.
  #
  # Only ECS and EXTERNAL are supported. Blue/green, linear and canary are done
  # natively by ECS, so CodeDeploy is not part of this module.
  ##############################################################################

  services_ecs = {
    for k, v in var.container_config : k => v
    if local.svc[k].deployment_controller == "ECS"
  }

  services_external = {
    for k, v in var.container_config : k => v
    if local.svc[k].deployment_controller == "EXTERNAL"
  }

  # ECS-controller services whose task definition Terraform should NOT manage.
  # Opt in per service for pipelines that roll images outside Terraform.
  services_ecs_unmanaged_td = {
    for k, v in local.services_ecs : k => v
    if try(v.service.ignore_task_definition_changes, false)
  }

  services_ecs_managed_td = {
    for k, v in local.services_ecs : k => v
    if !try(v.service.ignore_task_definition_changes, false)
  }

  ##############################################################################
  # ECS infrastructure IAM role
  #
  # Needed whenever ECS has to act on your infrastructure: shifting traffic
  # between target groups, attaching EBS volumes, or registering Lattice
  # targets. Each capability adds a different managed policy, so the three
  # subsets are tracked separately.
  ##############################################################################

  # Traffic shifting - advanced_configuration.role_arn is required by the
  # provider, so a BLUE_GREEN / LINEAR / CANARY service cannot plan without it.
  services_needing_lb_infrastructure_role = {
    for k, v in var.container_config : k => v
    if var.create_infrastructure_iam_role &&
    local.svc_resolved[k].shifts_traffic &&
    try(v.service.deployment_configuration.ecs_alb_service_role_arn, null) == null
  }

  services_needing_volume_infrastructure_role = {
    for k, v in var.container_config : k => v
    if var.create_infrastructure_iam_role && length(try(v.service.ebs_volumes, [])) > 0
  }

  services_needing_lattice_infrastructure_role = {
    for k, v in var.container_config : k => v
    if var.create_infrastructure_iam_role && length(try(v.service.vpc_lattice_configurations, [])) > 0
  }

  # One role per service, carrying whichever policies that service needs.
  services_needing_infrastructure_role = merge(
    local.services_needing_lb_infrastructure_role,
    local.services_needing_volume_infrastructure_role,
    local.services_needing_lattice_infrastructure_role,
  )

  # Explicit input wins; otherwise fall back to the role created above. Null
  # when neither applies, which the resources handle with try().
  infrastructure_iam_role_arns = {
    for k, v in var.container_config : k => try(
      coalesce(
        try(v.service.deployment_configuration.ecs_alb_service_role_arn, null),
        try(aws_iam_role.infrastructure[k].arn, null),
      ),
      null,
    )
  }

  # Every service name, whichever resource created it. Used by alarms and
  # autoscaling so they do not need to know which controller applies.
  service_names = merge(
    { for k, v in aws_ecs_service.main : k => v.name },
    { for k, v in aws_ecs_service.main_unmanaged_td : k => v.name },
    { for k, v in aws_ecs_service.external : k => v.name },
  )
}
