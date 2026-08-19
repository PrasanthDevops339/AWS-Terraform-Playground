variable "metric_namespace" {
  description = "CloudWatch namespace for PatchRunStatus and RebootOccurred. Splunk Observability scrapes this."
  type        = string
  default     = "Custom/PatchExecution"
}

variable "detect_document_name" {
  description = "Name of the Command document run on the instance. Must match the DocumentName referenced inside the trigger runbook."
  type        = string
  default     = "Detect-PatchReboot"
}

variable "trigger_document_name" {
  description = "Name of the Automation runbook targeted by EventBridge."
  type        = string
  default     = "Trigger-DetectPatchReboot"
}

variable "rule_name" {
  description = "EventBridge rule name."
  type        = string
  default     = "patch-command-complete-detect-reboot"
}

variable "patch_document_names" {
  description = "Patch documents to react to. Quick Setup patch policies commonly use the Association variant."
  type        = list(string)
  default = [
    "AWS-RunPatchBaseline",
    "AWS-RunPatchBaselineAssociation",
    "AWS-RunPatchBaselineWithHooks",
  ]
}

variable "automation_role_name" {
  description = "Name of the Automation execution role."
  type        = string
  default     = "patch-reboot-detection-automation"
}

variable "events_role_name" {
  description = "Name of the role EventBridge assumes to start the Automation."
  type        = string
  default     = "patch-reboot-detection-events"
}

variable "create_instance_metric_policy" {
  description = "Create a managed policy letting instances publish to metric_namespace. Set false if PutMetricData is granted in the AFT base instance profile instead."
  type        = bool
  default     = true
}

variable "instance_metric_policy_name" {
  description = "Name of the instance-side metric publishing policy."
  type        = string
  default     = "patch-execution-metric-publish"
}

variable "instance_role_names" {
  description = "Instance profile role names to attach the metric publishing policy to. AFT-vended roles carry generated suffixes, so pass resolved names or discover them upstream."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to created resources."
  type        = map(string)
  default     = {}
}
