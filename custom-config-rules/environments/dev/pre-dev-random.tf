# READ ME!!!
# Random String that needs to be added to every resource
# This is to prevent resources from sharing a name and overwriting your dev resources
# Use the following below to reference
# local.random_id

resource "random_string" "random_id" {
  numeric = true
  special = false
  upper   = false
  length  = 4
}

output "random_id" {
  description = "Random ID for resources. All deployed resources should have this in the name"
  value       = local.random_id
}

variable "is_pre_dev" {
  description = "Boolean for if this is a 'pre-dev' environment"
  default     = false
}

locals {
  random_id = var.is_pre_dev ? random_string.random_id.result : null
}
