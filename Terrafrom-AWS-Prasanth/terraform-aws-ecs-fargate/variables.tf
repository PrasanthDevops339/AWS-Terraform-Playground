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

// Removed TG creation support: protocol/health_check are no longer used here.
