##################################################
# Variables for AWS Organizations AMI Policy
##################################################

variable "org_root_or_ou_ids" {
  description = "List of AWS Organizations root or OU IDs to attach the AMI policies"
  type        = list(string)
  
  validation {
    condition     = alltrue([for id in var.org_root_or_ou_ids : can(regex("^(r-[0-9a-z]{4,32}|ou-[0-9a-z]{4,32}-[0-9a-z]{8,32})$", id))])
    error_message = "Must be valid AWS Organizations root ID (r-xxxx) or OU ID (ou-xxxx-xxxxxxxx)."
  }
}

variable "approved_ami_owner_accounts" {
  description = "List of approved AMI owner account IDs (golden AMI publishers and vendors)"
  type        = list(string)
  default = [
    "123456738923", # Ops golden AMIs
    "111122223333", # InfoBlox AMI publisher
    "444455556666", # Terraform Enterprise (TFE) AMI publisher
  ]
  
  validation {
    condition     = alltrue([for account in var.approved_ami_owner_accounts : can(regex("^[0-9]{12}$", account))])
    error_message = "All account IDs must be 12-digit strings."
  }
}

variable "exception_accounts" {
  description = "Map of exception account IDs to expiry dates (YYYY-MM-DD). Accounts are automatically included until expiry."
  type        = map(string)
  default = {
    "777788889999" = "2026-02-28" # AppTeam Sandbox exception
    "222233334444" = "2026-03-15" # M&A migration exception
  }
  
  validation {
    condition     = alltrue([for account, expiry in var.exception_accounts : can(regex("^[0-9]{12}$", account))])
    error_message = "All exception account IDs must be 12-digit strings."
  }
  
  validation {
    condition     = alltrue([for account, expiry in var.exception_accounts : can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", expiry))])
    error_message = "All expiry dates must be in YYYY-MM-DD format."
  }
}

variable "policy_mode" {
  description = "Policy enforcement mode: 'audit_mode' for testing, 'enabled' for enforcement"
  type        = string
  default     = "audit_mode"
  
  validation {
    condition     = contains(["audit_mode", "enabled"], var.policy_mode)
    error_message = "Policy mode must be either 'audit_mode' or 'enabled'."
  }
}

variable "policy_name_prefix" {
  description = "Prefix for policy names"
  type        = string
  default     = "ami-governance"
}

variable "exception_message" {
  description = "Message to display when AMI launch is blocked, including exception process details"
  type        = string
  default     = <<-EOT
    AMI Launch Denied: This EC2 instance launch was blocked because the AMI is not from an approved publisher.
    
    Approved AMI Publishers:
    - Ops Golden AMI Account: 123456738923
    - Approved Vendors: InfoBlox, Terraform Enterprise
    
    App teams are NOT allowed to build/bake custom AMIs. All customization must be done via user-data scripts at launch time.
    
    Exception Process:
    If you have a valid business need for an exception, submit a request via ServiceNow:
    1. Provide business justification and security review
    2. Specify account ID and required duration (max 90 days)
    3. Obtain approval from Security and Platform teams
    4. Exception will be implemented via GitOps with automatic expiry
    
    Contact: platform-team@company.com
  EOT
}

variable "workload_ou_ids" {
  description = "List of workload OU IDs where SCP will be applied (typically excludes security/ops OUs)"
  type        = list(string)
  default     = []
  
  validation {
    condition     = alltrue([for id in var.workload_ou_ids : can(regex("^ou-[0-9a-z]{4,32}-[0-9a-z]{8,32}$", id))])
    error_message = "Must be valid AWS Organizations OU IDs (ou-xxxx-xxxxxxxx)."
  }
}

variable "enable_declarative_policy" {
  description = "Whether to create and attach the declarative policy (EC2 Image Block + Allowed Images)"
  type        = bool
  default     = true
}

variable "enable_scp_policy" {
  description = "Whether to create and attach the SCP policy"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy   = "Terraform"
    Feature     = "AMI-Governance"
    Compliance  = "Required"
  }
}
