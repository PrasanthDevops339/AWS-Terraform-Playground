variable "environment" {
  description = "Environment which aligns to account 'dev', 'prd'"
  type        = string

  validation {
    condition     = contains(["dev", "prd"], var.environment)
    error_message = "Valid values for environment are 'dev' or 'prd'."
  }
}

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

variable "acme_playground_dev" {
  description = "ID of acme_playground_dev account"
  type        = string
}

variable "acme_cloudaws_afttest2" {
  description = "ID of acme_cloudaws_afttest2 account"
  type        = string
}

# ============================================================================
# Application OU IDs for exception AMI account restrictions
# Each application has its own OU containing dev, tst, prd accounts.
# Dummy account IDs are used here -- replace with real OU IDs before applying.
# ============================================================================

variable "pras_datalake_ou" {
  description = "OU ID for the Datalake application (accounts: 100000000001 dev, 100000000002 tst, 100000000003 prd)"
  type        = string
  default     = "ou-xxxx-datalake0"
}

variable "pras_transit_ou" {
  description = "OU ID for the Transit application (accounts: 200000000001 dev, 200000000002 tst, 200000000003 prd)"
  type        = string
  default     = "ou-xxxx-transit00"
}

variable "pras_agcydshbrd_ou" {
  description = "OU ID for the AgcyDshBrd application (accounts: 300000000001 dev, 300000000002 tst, 300000000003 prd)"
  type        = string
  default     = "ou-xxxx-agcydshr0"
}

variable "pras_termcond_ou" {
  description = "OU ID for the TermCond application (accounts: 400000000001 dev, 400000000002 tst, 400000000003 prd)"
  type        = string
  default     = "ou-xxxx-termcond0"
}

variable "pras_datasync_ou" {
  description = "OU ID for the DataSync application (accounts: 500000000001 dev, 500000000002 tst, 500000000003 prd)"
  type        = string
  default     = "ou-xxxx-datasync0"
}

variable "pras_claimsdata_ou" {
  description = "OU ID for the ClaimsData application (accounts: 600000000001 dev, 600000000002 tst, 600000000003 prd)"
  type        = string
  default     = "ou-xxxx-claimdat0"
}

