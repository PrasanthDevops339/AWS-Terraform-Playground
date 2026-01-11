variable "root" {
  description = "ID of root OU"
  type        = string
}

variable "exceptions" {
  description = "ID of exceptions OU"
  type        = string
}

variable "infrastructure" {
  description = "ID of infrastructure OU"
  type        = string
}

variable "infrastructure_dev" {
  description = "ID of infrastructure dev OU"
  type        = string
}

variable "infrastructure_tst" {
  description = "ID of infrastructure tst OU"
  type        = string
}

variable "infrastructure_prd" {
  description = "ID of infrastructure prd OU"
  type        = string
}

variable "sandbox" {
  description = "ID of sandbox OU"
  type        = string
}

variable "security" {
  description = "ID of security OU"
  type        = string
}

variable "suspended" {
  description = "ID of suspended OU"
  type        = string
}

variable "workloads" {
  description = "ID of workloads OU"
  type        = string
}

variable "workloads_dev" {
  description = "ID of workloads dev OU"
  type        = string
}

variable "workloads_tst" {
  description = "ID of workloads tst OU"
  type        = string
}

variable "workloads_prd" {
  description = "ID of workloads prd OU"
  type        = string
}
