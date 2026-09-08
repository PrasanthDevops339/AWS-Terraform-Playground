variable "organization_id" {
  description = "Actual AWS Organizations ID used in the rendered central bucket and KMS policy statements."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id)) && var.organization_id != "o-xxxxxxxxxx"
    error_message = "organization_id must be a real Organizations ID (o- followed by 10-32 lowercase letters/digits), not the template placeholder."
  }
}

variable "archive_bucket_name" {
  description = "Name of the existing central S3 bucket that stores patch outcome records. This module never creates or modifies the bucket, its policy, or its KMS key -- central policy statements are rendered by the primary Lambda deployment."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.archive_bucket_name))
    error_message = "archive_bucket_name must be a valid 3-63 character S3 bucket name."
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
    condition     = length(var.archive_s3_prefix) > 0 && !can(regex("[?*]", var.archive_s3_prefix))
    error_message = "archive_s3_prefix must not be empty or contain IAM wildcards."
  }

  nullable = false
}

variable "archive_kms_key_arn" {
  description = "ARN of the central account's KMS CMK that encrypts the archive bucket. Used only to encrypt the S3 PutObject call from this module; never used for member-account resources (log group, SQS)."
  type        = string
  default     = null
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
  description = "Permissions boundary ARN to attach to the writer role, if the org's SCPs mandate one."
  type        = string
  default     = null
}

variable "enable_enrichment" {
  description = "Enable bounded SSM lookups for aggregate invocation status, command operation and optional context. Disable only if degraded unknown outcomes are acceptable."
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

variable "rules_enabled" {
  description = "Whether the three SSM EventBridge rules are ENABLED. Defaults to a dormant deployment; stored packages, logs and canary requests can still incur charges. Does not affect the canary rule, which is always enabled independent of this flag."
  type        = bool
  default     = false
  nullable    = false
}

variable "tags" {
  description = "Tags applied to all taggable resources created by this module."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "member_account_id" {
  description = "Target AFT member account. AWS provider refuses other account IDs."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.member_account_id))
    error_message = "member_account_id must contain exactly twelve digits."
  }
}

variable "primary_region" {
  description = "First patching region and provider used to create the account-wide role."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Second patching region; must differ from primary_region."
  type        = string
  default     = "us-west-2"
  validation {
    condition     = var.secondary_region != var.primary_region
    error_message = "The two example regions must differ."
  }
}
