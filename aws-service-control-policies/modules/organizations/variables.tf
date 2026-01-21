variable "policy_name" {
  description = "(Optional) The friendly name to assign to the policy"
  type        = string
  default     = null
}

variable "file_date" {
  description = "(Optional) Select policy based on file date"
  type        = string
  default     = null
}

variable "policy_vars" {
  description = "(Optional) Map of arguments to pass into policy JSON files"
  type        = map(any)
  default     = {}
}

variable "description" {
  description = "(Optional) A description to assign to the policy"
  type        = string
  default     = null
}

variable "type" {
  description = "(Optional) The type of policy to create"
  type        = string
  default     = "SERVICE_CONTROL_POLICY"
}

variable "skip_destroy" {
  description = "(Optional) If set to true, destroy will not delete the policy and instead just remove the resource from state"
  type        = bool
  default     = false
}

variable "create_policy" {
  description = "(Optional) Create policy or only attach policy by passing in policy_id variable"
  type        = bool
  default     = true
}

variable "policy_id" {
  description = "(Optional) The unique identifier (ID) of the policy that you want to attach to the target"
  type        = string
  default     = null
}

variable "target_ids" {
  description = "(Optional) The unique identifier (ID) of the root, organizational unit, or account number that"
  type        = set(string)
  default     = []
}

variable "tags" {
  description = "(Optional) A map of tags to add to all related resources"
  type        = map(string)
  default     = {}
}

variable "add_random_characters" {
  description = "(Optional) Add random characters to the end of policy name"
  type        = bool
  default     = false
}
