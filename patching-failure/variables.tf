variable "account_id" {
  description = "Target AWS account. Set as a TFE workspace variable; TFE assumes prasa-tfe-assume-role in this account, and allowed_account_ids guards against a mismatch. Required (no empty default) so an unset value fails validation instead of building an invalid role ARN."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }

  nullable = false
}

variable "region" {
  description = "The single region this POC deploys into. Must be a region where the Quick Setup patch policy runs."
  type        = string
  default     = "us-east-2"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "region must be an AWS region name such as us-east-1."
  }

  nullable = false
}

variable "organization_id" {
  description = "AWS Organizations ID rendered into the central bucket and KMS policy statements (output central_prerequisites)."
  type        = string

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id)) && var.organization_id != "o-xxxxxxxxxx"
    error_message = "organization_id must be an Organizations ID (o- followed by 10-32 lowercase letters/digits), not the template placeholder."
  }

  nullable = false
}

variable "name_prefix" {
  description = "Prefix applied to resource names created here (rules, Lambda, package bucket, runtime policy)."
  type        = string
  default     = "patch-outcome"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,40}$", var.name_prefix))
    error_message = "name_prefix must be lowercase alphanumeric/hyphen, 3-41 chars, starting with alphanumeric."
  }

  # Final account-alias-prefixed names are checked in main.tf.
  nullable = false
}

variable "archive_bucket_name" {
  description = "Name of the existing central S3 bucket that stores patch outcome records. Never created or modified here -- resolved policy statements are output for the bucket owners to merge."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.archive_bucket_name))
    error_message = "archive_bucket_name must be a valid 3-63 character S3 bucket name."
  }

  nullable = false
}

variable "archive_s3_prefix" {
  description = "S3 key prefix for outcome records. Deliberately a SIBLING of the existing patchingsolution/ prefix, not a child of it, so s3tofirehose does not label these records with the RunPatchBaseline stdout sourcetype."
  type        = string
  default     = "patchingsolution-events/outcomes"

  validation {
    condition     = !can(regex("^/", var.archive_s3_prefix)) && !can(regex("/$", var.archive_s3_prefix))
    error_message = "archive_s3_prefix must not have a leading or trailing slash."
  }

  validation {
    condition     = length(var.archive_s3_prefix) > 0 && !can(regex("[?*]", var.archive_s3_prefix))
    error_message = "archive_s3_prefix must not be empty or contain IAM wildcards."
  }

  nullable = false
}

variable "archive_kms_key_arn" {
  description = "Key ARN (not an alias) of the central account's KMS CMK. The central bucket is SSE-KMS, so every PutObject names this key. Used only for archive writes."
  type        = string

  validation {
    condition     = can(regex("^arn:[a-z-]+:kms:[a-z0-9-]+:[0-9]{12}:key/[A-Za-z0-9-]+$", var.archive_kms_key_arn))
    error_message = "archive_kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>), not an alias."
  }

  nullable = false
}

variable "archive_object_acl" {
  description = "Optional bucket-owner-full-control ACL. Prefer null for BucketOwnerEnforced; ACL-enabled cross-account buckets may require it."
  type        = string
  default     = null

  validation {
    condition     = var.archive_object_acl == null || var.archive_object_acl == "bucket-owner-full-control"
    error_message = "archive_object_acl must be null or bucket-owner-full-control."
  }
}

variable "lambda_package_bucket_name" {
  description = "Override name for the S3 bucket that holds the Lambda deployment zip. Leave null to use '<name_prefix>-pkg-<account-id>-<region>'."
  type        = string
  default     = null

  validation {
    condition     = var.lambda_package_bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", coalesce(var.lambda_package_bucket_name, "xx")))
    error_message = "lambda_package_bucket_name must be a valid S3 bucket name (3-63 chars, lowercase)."
  }
}

variable "patch_document_name_prefix" {
  description = "Prefix match for detail.document-name in every EventBridge pattern. Quick Setup patch policies run AWS-RunPatchBaseline; the prefix also catches ...Association and ...WithHooks documents."
  type        = string
  default     = "AWS-RunPatchBaseline"

  validation {
    condition     = length(var.patch_document_name_prefix) > 0
    error_message = "patch_document_name_prefix must not be empty."
  }

  nullable = false
}

variable "invocation_failure_statuses" {
  description = "detail.status values that match the EC2 Command Invocation Status-change Notification failure rule. Do NOT remove Terminated: under zero-tolerance rate control, a Terminated instance was never touched and is unpatched."
  type        = list(string)
  default     = ["Failed", "TimedOut", "Cancelled", "Undeliverable", "Terminated", "DeliveryTimedOut", "Delivery Timed Out", "ExecutionTimedOut", "Execution Timed Out", "InvalidPlatform", "Invalid Platform", "AccessDenied", "Access Denied"]

  validation {
    condition     = contains(var.invocation_failure_statuses, "Terminated")
    error_message = "invocation_failure_statuses must include \"Terminated\": a Terminated instance is unpatched, which is a failure, not a benign skip."
  }

  nullable = false
}

variable "command_failure_statuses" {
  description = "detail.status values that match the EC2 Command Status-change Notification failure rule."
  type        = list(string)
  default     = ["Failed", "TimedOut", "Cancelled", "Undeliverable", "Incomplete", "AccessDenied", "Access Denied", "DeliveryTimedOut", "Delivery Timed Out", "RateExceeded", "Rate Exceeded", "No Instances In Tag"]

  validation {
    condition     = length(var.command_failure_statuses) > 0
    error_message = "command_failure_statuses must not be empty."
  }

  nullable = false
}

variable "rules_enabled" {
  description = "Whether the three SSM EventBridge rules are ENABLED. Defaults to dormant until the canary is verified. Does not affect the canary rule."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_canary" {
  description = "Create a canary EventBridge rule matching source = custom.patch-canary, always ENABLED. It proves the plumbing (Lambda, role, bucket policy, KMS grant) without impersonating a real SSM event."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_enrichment" {
  description = "Enable bounded SSM lookups for aggregate invocation status, command operation and optional context. Disable only if degraded unknown outcomes are acceptable."
  type        = bool
  default     = true
  nullable    = false
}

variable "include_instance_tags" {
  description = "Whether the Lambda enriches not-attempted records with instance tags (Name, Application, Owner, patch:wave) via DescribeInstances."
  type        = bool
  default     = true
  nullable    = false
}

variable "app_log_group_name" {
  description = "Existing CloudWatch Logs group (same account and region) the Lambda writes to. Lambda creates its own log streams in it; retention and encryption belong to the group's owner and are not managed here."
  type        = string
  default     = "app_log/"

  validation {
    condition     = length(var.app_log_group_name) > 0
    error_message = "app_log_group_name must not be empty."
  }

  nullable = false
}

variable "lambda_package_kms_key_arn" {
  description = "Key ARN of a same-account, same-region CMK that encrypts the Lambda deployment-zip bucket (SSE-KMS). Its key policy must let the deploying role (prasa-tfe-assume-role) encrypt and decrypt."
  type        = string

  validation {
    condition     = can(regex("^arn:[a-z-]+:kms:[a-z0-9-]+:[0-9]{12}:key/[A-Za-z0-9-]+$", var.lambda_package_kms_key_arn))
    error_message = "lambda_package_kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>), not an alias."
  }

  # Same account and region are checked by a precondition in main.tf.
  nullable = false
}

variable "reserved_concurrency" {
  description = "Reserved concurrency for the Lambda. Null means unreserved: throttling would fire exactly when zero-tolerance rate control produces its burst of events."
  type        = number
  default     = null
}

variable "log_level" {
  description = "Log level passed to the Lambda as LOG_LEVEL."
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.log_level)
    error_message = "log_level must be one of DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }

  nullable = false
}

variable "writer_role_name" {
  description = "Exact IAM role name for the Lambda execution role. The central bucket and KMS policies authorize it by ArnLike arn:<partition>:iam::*:role/<path><name>, so keep it fixed."
  type        = string
  default     = "patch-outcome-s3-writer"

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.writer_role_name))
    error_message = "writer_role_name must be 1-64 IAM role-name characters (no slash or wildcard)."
  }

  nullable = false
}

variable "iam_role_path" {
  description = "IAM path for the writer role, in case SCPs or permissions boundaries mandate one."
  type        = string
  default     = "/"

  validation {
    condition     = can(regex("^/([A-Za-z0-9+=,.@_-]+/)*$", var.iam_role_path))
    error_message = "iam_role_path must be / or slash-delimited IAM path segments without wildcards."
  }

  nullable = false
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary ARN to attach to the writer role, if required."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all taggable resources."
  type        = map(string)
  default     = {}
  nullable    = false
}
