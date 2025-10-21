variable "account_id" {
  type = string
}

# Identifier or ARN of the source DB instance for replica creation
variable "replicate_source_db" {
  type        = string
  description = "(Required) The source DB instance identifier/ARN to replicate from."
}
