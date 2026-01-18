variable "environment" {
  description = "Name of the environment, is set to 'pre-dev' if not on main branch"
  type        = string
  default     = "dev"
}

variable "account_number" {
  type = string
}
