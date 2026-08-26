variable "account_id" {
  description = "AWS account ID in which the example resources will be created."
  type        = string
}

variable "tags" {
  description = "Additional tags to assign to resources."
  default = {
    env = "dev"
  }
}
