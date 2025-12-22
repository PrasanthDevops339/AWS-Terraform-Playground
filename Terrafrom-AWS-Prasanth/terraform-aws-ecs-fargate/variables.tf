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
      alltrue([ for tg in var.target_groups : try(tg.target_group_arn != null && tg.target_group_arn != "", false) ])
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
      enable   = optional(bool, false)
      rollback = optional(bool, false)
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
    weight           = optional(number, 1)
    base             = optional(number, 0)
  }))
  default = [
    {
      capacity_provider = "FARGATE"
      weight           = 1
      base             = 0
    }
  ]
}

// Removed TG creation support: protocol/health_check are no longer used here.
