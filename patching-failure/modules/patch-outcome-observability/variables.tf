variable "name_prefix" {
  description = "Prefix applied to all resource names created by this module (rules, DLQs, log group derivation, etc.)."
  type        = string
  default     = "patch-outcome"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,40}$", var.name_prefix))
    error_message = "name_prefix must be lowercase alphanumeric/hyphen, 3-41 chars, starting with alphanumeric."
  }

  # Longest derived name is "${name_prefix}-invocation-success" (rule) and
  # "${name_prefix}-target-dlq" (SQS, hard 80-char limit). 41 + 17 keeps both safe.
  nullable = false
}

variable "archive_bucket_name" {
  description = "Name of the existing central S3 bucket that stores patch outcome records. This module never creates or modifies the bucket, its policy, or its KMS key -- it only writes to it and renders the statements the bucket owner must merge (see the central_prerequisites output)."
  type        = string

  validation {
    condition     = length(var.archive_bucket_name) > 0
    error_message = "archive_bucket_name is required."
  }

  nullable = false
}

variable "archive_s3_prefix" {
  description = "S3 key prefix for outcome records. Deliberately a SIBLING of the existing patchingsolution/ prefix, not a child of it: if s3tofirehose matches on the patchingsolution/ prefix, dropping this JSON inside it would make the labeling script tag these records with the RunPatchBaseline stdout sourcetype. They would parse as garbage into the wrong index -- which looks like success from the AWS side and is worse than never arriving."
  type        = string
  default     = "patchingsolution-events/outcomes"

  validation {
    condition     = !can(regex("^/", var.archive_s3_prefix)) && !can(regex("/$", var.archive_s3_prefix))
    error_message = "archive_s3_prefix must not have a leading or trailing slash."
  }

  validation {
    condition     = length(var.archive_s3_prefix) > 0
    error_message = "archive_s3_prefix must not be empty."
  }

  nullable = false
}

variable "archive_kms_key_arn" {
  description = "ARN of the central account's KMS CMK that encrypts the archive bucket. Used only to encrypt the S3 PutObject call from this module; never used for member-account resources (log group, SQS)."
  type        = string
  default     = null
}

variable "lambda_package_bucket_name" {
  description = "Override name for the per-account S3 bucket that holds the Lambda deployment zip (the shared terraform-aws-lambda module deploys from S3, not a local file). Leave null to use the computed name '<name_prefix>-pkg-<account-id>'. Set this if an SCP or naming standard requires a specific bucket name."
  type        = string
  default     = null

  validation {
    condition     = var.lambda_package_bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", coalesce(var.lambda_package_bucket_name, "xx")))
    error_message = "lambda_package_bucket_name must be a valid S3 bucket name (3-63 chars, lowercase)."
  }
}

variable "archive_object_acl" {
  description = "Object ACL to set on PutObject, e.g. bucket-owner-full-control. Set this ONLY if the central bucket has S3 ACLs enabled (not BucketOwnerEnforced). See open question 1 in BUILD-INSTRUCTIONS: with ACLs enabled and no bucket-owner-full-control, every PutObject still returns 200, objects silently accumulate, and the bucket owner gets AccessDenied reading its own objects -- nothing errors anywhere. Leave null when the bucket uses BucketOwnerEnforced."
  type        = string
  default     = null
}

variable "writer_role_name" {
  description = "Exact IAM role name for the Lambda execution role. Must be IDENTICAL in every member account: the central bucket policy and KMS key policy authorize this role by ArnLike arn:<partition>:iam::*:role/<name>. Do not derive it from name_prefix, append a suffix, or let Terraform randomize it."
  type        = string
  default     = "patch-outcome-s3-writer"

  validation {
    condition     = !can(regex("[*/]", var.writer_role_name))
    error_message = "writer_role_name must not contain '*' or '/'."
  }

  validation {
    condition     = length(var.writer_role_name) >= 1 && length(var.writer_role_name) <= 64
    error_message = "writer_role_name must be 1-64 characters (IAM role name limit)."
  }

  nullable = false
}

variable "patch_document_name_prefix" {
  description = "Prefix match for detail.document-name in every EventBridge pattern. The default also catches ...Association document names."
  type        = string
  default     = "AWS-RunPatchBaseline"

  validation {
    condition     = length(var.patch_document_name_prefix) > 0
    error_message = "patch_document_name_prefix must not be empty."
  }

  nullable = false
}

variable "invocation_failure_statuses" {
  description = "detail.status values that match the EC2 Command Invocation Status-change Notification failure rule. Do NOT remove Terminated: under zero-tolerance rate control, a Terminated instance was never touched and is unpatched, which is a failure, not a benign skip."
  type        = list(string)
  default     = ["Failed", "TimedOut", "Cancelled", "Undeliverable", "Terminated"]

  validation {
    condition     = contains(var.invocation_failure_statuses, "Terminated")
    error_message = "invocation_failure_statuses must include \"Terminated\": a Terminated instance is unpatched, which is a failure, not a benign skip."
  }

  nullable = false
}

variable "command_failure_statuses" {
  description = "detail.status values that match the EC2 Command Status-change Notification failure rule."
  type        = list(string)
  default     = ["Failed", "TimedOut", "Cancelled", "Undeliverable", "Incomplete", "AccessDenied", "DeliveryTimedOut"]

  validation {
    condition     = length(var.command_failure_statuses) > 0
    error_message = "command_failure_statuses must not be empty."
  }

  nullable = false
}

variable "rules_enabled" {
  description = "Whether the three SSM EventBridge rules are ENABLED. Set false to deploy this module dormant (cost at rest is $0) and arm it later by flipping this variable. Does not affect the canary rule, which is always enabled independent of this flag."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_canary" {
  description = "Create a canary EventBridge rule matching source = custom.patch-canary, always ENABLED regardless of rules_enabled. PutEvents rejects any source beginning with aws., so a canary event can never impersonate a real SSM event -- it only proves the plumbing (Lambda, role, bucket policy, KMS grant) is wired correctly. With no metrics tier, this is the only end-to-end liveness proof for a solution that otherwise sits dormant."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_enrichment" {
  description = "Whether the Lambda makes the enrichment API calls (GetCommandInvocation, ListCommands, DescribeInstanceInformation) needed to classify not-attempted outcomes. Do NOT disable in production: it is the only source of the Terminated status detail, without which not-attempted instances are indistinguishable from any other failure."
  type        = bool
  default     = true
  nullable    = false
}

variable "include_instance_tags" {
  description = "Whether the Lambda enriches not-attempted records with instance tags (Name, Application, Owner, patch:wave) via DescribeInstances. Set false if Splunk already has an instance-ID -> owner lookup, to save ~139 bytes and one API call per record and avoid stale tags frozen into an immutable object."
  type        = bool
  default     = true
  nullable    = false
}

variable "lambda_log_retention_in_days" {
  description = "CloudWatch Logs retention for the Lambda's own log group -- the in-account triage tier, not a debug log."
  type        = number
  default     = 365

  validation {
    condition = contains(
      [1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.lambda_log_retention_in_days
    )
    error_message = "lambda_log_retention_in_days must be one of the CloudWatch Logs allowed retention values."
  }

  nullable = false
}

variable "local_kms_key_arn" {
  description = "Member-account KMS key ARN used to encrypt the Lambda's own log group, if the org has one. This is NOT the central archive key -- that key lives in the central account and using it here would require a cross-account grant for logs.<region>.amazonaws.com in every one of ~450 accounts. Leave null to use CloudWatch Logs default encryption."
  type        = string
  default     = null
}

variable "reserved_concurrency" {
  description = "Reserved concurrency for the Lambda. Left null (no reserved concurrency argument set) by default: throttling would fire exactly when zero-tolerance rate control produces its ~37-events-at-once burst."
  type        = number
  default     = null
}

variable "log_level" {
  description = "Log level passed to the Lambda as LOG_LEVEL. One of DEBUG, INFO, WARNING, ERROR, CRITICAL (Python logging levels)."
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.log_level)
    error_message = "log_level must be one of DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }

  nullable = false
}

variable "iam_role_path" {
  description = "IAM path for the writer role, in case SCPs or permissions boundaries mandate one."
  type        = string
  default     = "/"

  validation {
    condition     = can(regex("^/.*/$|^/$", var.iam_role_path))
    error_message = "iam_role_path must begin and end with '/' (e.g. '/' or '/service-role/')."
  }

  nullable = false
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary ARN to attach to the writer role, if the org's SCPs mandate one."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all taggable resources created by this module."
  type        = map(string)
  default     = {}
  nullable    = false
}
