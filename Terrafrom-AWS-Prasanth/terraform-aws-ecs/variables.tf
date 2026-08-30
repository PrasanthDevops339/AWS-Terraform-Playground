##############################
# Cluster variables
##############################
variable "create_cluster" {
  description = "Whether to create cluster"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the cluster (up to 255 letters, numbers, hyphens, and underscores)"
  type        = string
}

variable "existing_cluster_arn" {
  description = "ARN of a pre-existing ECS cluster to deploy services into. Required when create_cluster is false"
  type        = string
  default     = null

  validation {
    condition     = var.create_cluster || var.existing_cluster_arn != null
    error_message = "existing_cluster_arn must be set when create_cluster is false, otherwise services have no cluster to join."
  }
}

variable "cluster_configuration" {
  description = "The execute command configuration for the cluster."
  type        = list(map(any))
  default     = []
}

variable "cluster_settings" {
  description = "List of configuration block(s) with cluster settings. For example, this can be used to enable CloudWatch Container Insights for a cluster"
  type = list(object({
    name  = string
    value = string
  }))
  default = [
    {
      name  = "containerInsights"
      value = "enabled"
    }
  ]
}

##############################
# Task definition variables
##############################
variable "container_config" {
  description = "Service configuration"
  type        = any
  default     = {}

  # CodeDeploy support was removed from this module. Without this check a
  # leftover CODE_DEPLOY controller would match neither the ECS nor the
  # EXTERNAL service grouping, and the service would silently not be created.
  validation {
    condition = alltrue([
      for k, v in var.container_config :
      contains(["ECS", "EXTERNAL"], try(v.service.deployment_controller.type, "ECS"))
    ])
    error_message = "deployment_controller.type must be ECS or EXTERNAL. CodeDeploy is not supported by this module - use the ECS-native BLUE_GREEN, LINEAR or CANARY deployment strategies instead, which need no CodeDeploy application, deployment group or AppSpec."
  }
}

variable "container_name" {
  description = "(DEPRECATED - supply container name in container_config instead.) Name of the container"
  type        = string
  default     = ""
}

variable "execution_iam_roles" {
  description = "(DEPRECATED - supply execution role in container_config instead.) ARN of the task execution role"
  type        = string
  default     = null
}

variable "tags" {
  description = "Default tags to apply"
  type        = map(string)
  default     = {}
}

variable "efs_volumes" {
  description = "EFS volume definitions"
  type        = list(any)
  default     = []
}

##############################
# ECS service variables
##############################
variable "load_balanced" {
  description = "Set to true if the load balancer is required."
  type        = bool
  default     = true
}

variable "task_container_port" {
  description = "The port number on the container that is bound to the user-specified or automatically assigned host port"
  type        = number
  default     = 80
}

variable "target_groups" {
  description = "Target group config to associate with the ECS service. Each entry must provide target_group_arn from the external ALB module, plus container mapping settings."
  type        = any
  default     = []

  # Validation: If load balanced, ensure ARNs are provided for all entries
  validation {
    condition = (
      var.load_balanced == false ||
      length(var.target_groups) == 0 ||
      alltrue([for tg in var.target_groups : try(tg.target_group_arn != null && tg.target_group_arn != "", false)])
    )
    error_message = "When load_balanced is true, each target_groups entry must include a non-empty target_group_arn from the ALB module."
  }
}

variable "vpc_id" {
  description = "The VPC ID."
  type        = string
}

##############################
# Service Connect variables
##############################
variable "enable_service_connect" {
  description = "Whether to enable service connect for the cluster"
  type        = bool
  default     = false
}

variable "service_connect_configuration" {
  description = "Service connect configuration for the cluster"
  type = object({
    enabled   = optional(bool, false)
    namespace = optional(string, null)
    log_configuration = optional(object({
      log_driver = optional(string, "awslogs")
      options    = optional(map(string), {})
      secret_options = optional(list(object({
        name       = string
        value_from = string
      })), [])
    }), null)
  })
  default = {
    enabled = false
  }
}

##############################
# Deployment Strategy variables
##############################

variable "deployment_strategy_default" {
  description = <<-EOT
    Default ECS-native deployment strategy applied to all services that do not
    specify their own strategy via container_config[key].service.deployment_configuration.strategy.

    These are performed natively by ECS. No CodeDeploy application, deployment
    group, AppSpec or service role is involved anywhere in this module.

    Valid values (AWS provider >= 6.4.0):
      ROLLING    — classic rolling update with circuit breaker (default)
      BLUE_GREEN — full env alongside old; instant traffic shift; bake time
      LINEAR     — gradual % traffic shift, e.g. 25% every 5 min
      CANARY     — small canary %, bake, then full cutover
  EOT
  type        = string
  default     = "ROLLING"

  validation {
    condition     = contains(["ROLLING", "BLUE_GREEN", "LINEAR", "CANARY"], var.deployment_strategy_default)
    error_message = "deployment_strategy_default must be ROLLING, BLUE_GREEN, LINEAR, or CANARY."
  }
}

variable "deployment_configuration" {
  description = "Default deployment configuration for services"
  type = object({
    deployment_circuit_breaker = optional(object({
      enable   = optional(bool, false)
      rollback = optional(bool, false)
    }), null)
    maximum_percent         = optional(number, 200)
    minimum_healthy_percent = optional(number, 100)
    alarms = optional(object({
      enable      = optional(bool, false)
      rollback    = optional(bool, false)
      alarm_names = optional(list(string), [])
    }), null)
  })
  default = {
    maximum_percent         = 200
    minimum_healthy_percent = 100
  }
}

##############################
# Capacity Provider variables
##############################
variable "capacity_providers" {
  description = "List of capacity providers to associate with the cluster"
  type        = list(string)
  default     = ["FARGATE", "FARGATE_SPOT"]
}

variable "default_capacity_provider_strategy" {
  description = "Default capacity provider strategy for the cluster"
  type = list(object({
    capacity_provider = string
    weight            = optional(number, 1)
    base              = optional(number, 0)
  }))
  default = [
    {
      capacity_provider = "FARGATE"
      weight            = 1
      base              = 0
    }
  ]
}

// Removed TG creation support: protocol/health_check are no longer used here.

##############################
# ECS infrastructure IAM role
##############################

variable "create_infrastructure_iam_role" {
  description = <<-EOT
    Whether to create the ECS infrastructure IAM role for services that need it.

    This is the role ECS assumes to act on your infrastructure: reweighting ALB
    listener rules during BLUE_GREEN / LINEAR / CANARY traffic shifting,
    attaching EBS volumes at task launch, and registering VPC Lattice targets.

    advanced_configuration.role_arn is required by the AWS provider, so leaving
    this false means every traffic-shifting service must supply
    service.deployment_configuration.ecs_alb_service_role_arn itself.
  EOT
  type        = bool
  default     = true
}

variable "infrastructure_iam_role_permissions_boundary" {
  description = "Permissions boundary ARN applied to the ECS infrastructure IAM roles"
  type        = string
  default     = null
}

##############################
# Launch type variables
##############################

variable "launch_type_default" {
  description = <<-EOT
    Default launch type for services that do not set their own via
    container_config[key].service.launch_type.

      FARGATE  — serverless tasks, awsvpc network mode, no instances to manage
      EC2      — tasks placed on container instances from a capacity provider
      EXTERNAL — ECS Anywhere, tasks on self-managed infrastructure

    Defaults to FARGATE so existing callers are unaffected by the addition of
    EC2 support.
  EOT
  type        = string
  default     = "FARGATE"

  validation {
    condition     = contains(["FARGATE", "EC2", "EXTERNAL"], var.launch_type_default)
    error_message = "launch_type_default must be FARGATE, EC2, or EXTERNAL."
  }
}

##############################
# EC2 capacity provider variables
#
# Each entry builds launch template -> Auto Scaling group -> ECS capacity
# provider. This is what makes the EC2 launch type usable: without registered
# container instances an EC2 service has nowhere to place tasks.
#
# Services reference a provider by name in their capacity_provider_strategy:
#   "<account_alias>-<cluster_name>-<key>"
# or read it from the capacity_provider_names output.
##############################

variable "ec2_capacity_providers" {
  description = "Map of EC2 Auto Scaling group capacity providers to create for the cluster. Empty for a Fargate-only cluster."

  type = map(object({
    # ---- Instances ----
    instance_type = optional(string, "t3.medium")

    # Leave ami_id null to track the current ECS-optimized AMI from SSM.
    ami_id            = optional(string, null)
    ami_ssm_parameter = optional(string, "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id")

    key_name                    = optional(string, null)
    associate_public_ip_address = optional(bool, false)
    instance_profile_arn        = optional(string, null)

    root_volume_size_gb    = optional(number, 30)
    root_volume_type       = optional(string, "gp3")
    root_volume_encrypted  = optional(bool, true)
    root_volume_kms_key_id = optional(string, null)

    # IMDSv2 required. Hop limit 2 lets bridge-network containers reach IMDS.
    metadata_http_tokens                 = optional(string, "required")
    metadata_http_put_response_hop_limit = optional(number, 2)

    enable_monitoring = optional(bool, true)

    # Appended to the ECS agent bootstrap user data.
    additional_user_data = optional(string, "")

    # ---- Networking ----
    vpc_id             = string
    subnet_ids         = list(string)
    security_group_ids = optional(list(string), [])

    create_security_group = optional(bool, true)

    security_group_ingress_rules = optional(list(object({
      description                  = optional(string, "Container instance ingress")
      ip_protocol                  = string
      from_port                    = optional(number, null)
      to_port                      = optional(number, null)
      cidr_ipv4                    = optional(string, null)
      cidr_ipv6                    = optional(string, null)
      referenced_security_group_id = optional(string, null)
      prefix_list_id               = optional(string, null)
    })), [])

    security_group_egress_rules = optional(list(object({
      description                  = optional(string, "Container instance egress")
      ip_protocol                  = string
      from_port                    = optional(number, null)
      to_port                      = optional(number, null)
      cidr_ipv4                    = optional(string, null)
      cidr_ipv6                    = optional(string, null)
      referenced_security_group_id = optional(string, null)
      prefix_list_id               = optional(string, null)
    })), [])

    # ---- Auto Scaling group ----
    min_size         = optional(number, 0)
    max_size         = optional(number, 10)
    desired_capacity = optional(number, null)

    # Non-empty switches the ASG to a mixed instances policy, which is how
    # Spot capacity is diversified across instance types.
    instance_types_override                  = optional(list(string), [])
    on_demand_base_capacity                  = optional(number, 0)
    on_demand_percentage_above_base_capacity = optional(number, 100)
    spot_allocation_strategy                 = optional(string, "price-capacity-optimized")

    health_check_grace_period = optional(number, 300)
    capacity_rebalance        = optional(bool, true)

    # ---- ECS managed scaling ----
    managed_scaling_status          = optional(string, "ENABLED")
    managed_scaling_target_capacity = optional(number, 100)
    managed_scaling_min_step_size   = optional(number, 1)
    managed_scaling_max_step_size   = optional(number, 10)
    managed_scaling_instance_warmup = optional(number, 300)

    # Stops the ASG terminating an instance that is still running tasks.
    managed_termination_protection = optional(string, "ENABLED")
    managed_draining               = optional(string, "ENABLED")
  }))

  default = {}

  validation {
    condition = alltrue([
      for k, cp in var.ec2_capacity_providers : length(cp.subnet_ids) > 0
    ])
    error_message = "Each EC2 capacity provider must specify at least one subnet."
  }

  validation {
    condition = alltrue([
      for k, cp in var.ec2_capacity_providers :
      contains(["ENABLED", "DISABLED"], cp.managed_termination_protection)
    ])
    error_message = "managed_termination_protection must be ENABLED or DISABLED."
  }

  validation {
    condition = alltrue([
      for k, cp in var.ec2_capacity_providers : cp.max_size >= cp.min_size
    ])
    error_message = "Each EC2 capacity provider must have max_size >= min_size."
  }
}

