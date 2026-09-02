variable "account_id" {
  type = string
}

locals {
  # Shared by both module calls so they cannot drift. The cognito module only
  # accepts null, "us-east-1" or "us-east-2".
  target_region = "us-east-1"
}
