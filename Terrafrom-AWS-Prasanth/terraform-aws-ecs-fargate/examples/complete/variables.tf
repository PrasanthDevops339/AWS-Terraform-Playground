variable "account_id" {
  type = string
}

variable "tags" {
  default = {
    env = "dev"
  }
}
