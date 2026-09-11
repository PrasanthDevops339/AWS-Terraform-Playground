variable "name" {
  description = "Unique factory name, including environment."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,35}$", var.name))
    error_message = "Use 3-36 lowercase letters, digits and hyphens."
  }
}
variable "account_id" {
  description = "Explicit target AWS account ID; provider also enforces allowed_account_ids."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Supply a twelve-digit AWS account ID."
  }
}
variable "organization_id" {
  description = "Organization permitted to pull approved releases."
  type        = string
  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id))
    error_message = "Supply an AWS Organizations ID."
  }
}
variable "primary_region" {
  type        = string
  default     = "us-east-2"
  description = "Build and release control-plane Region."
}
variable "secondary_region" {
  type        = string
  default     = "us-east-1"
  description = "Approved-image replication Region."
}
variable "vpc_id" {
  type        = string
  description = "Existing dedicated build VPC."
}
variable "subnet_id" {
  type        = string
  description = "Private build subnet with approved egress and service connectivity."
}
variable "egress_cidrs" {
  description = "Approved HTTPS destinations/proxies; unrestricted internet CIDRs are rejected."
  type        = set(string)
  validation {
    condition     = length(var.egress_cidrs) > 0 && alltrue([for v in var.egress_cidrs : can(cidrnetmask(v)) && v != "0.0.0.0/0" && v != "::/0"])
    error_message = "Supply explicit approved egress CIDRs."
  }
}
variable "build_host_ami" {
  description = "Approved x86_64 Image Builder host AMI with Docker, SSM and host security prerequisites."
  type        = string
  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.build_host_ami))
    error_message = "Supply a pinned AMI ID."
  }
}
variable "parent_image" {
  description = "Approved standard AWS AL2023 container pinned by sha256 digest."
  type        = string
  validation {
    condition     = can(regex("^public\\.ecr\\.aws/amazonlinux/amazonlinux@sha256:[0-9a-f]{64}$", var.parent_image))
    error_message = "Use the standard AL2023 public ECR image with an immutable digest."
  }
}
variable "source_revision" {
  description = "Reviewed Git commit recorded in image metadata and rebuild budget."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.source_revision))
    error_message = "Supply the full Git SHA."
  }
}
variable "recipe_version" {
  description = "Image Builder semantic version; increment whenever components or recipe content change."
  type        = string
  default     = "1.0.0"
}
variable "release_series" {
  type        = string
  default     = "1.0"
  description = "Reviewed major.minor; patch is allocated by the release ledger."
}
variable "certificate_bundle" {
  description = "Local reviewed public enterprise CA PEM bundle; never a private key."
  type        = string
  validation {
    condition     = can(regex("BEGIN CERTIFICATE", file(var.certificate_bundle))) && !can(regex("PRIVATE KEY", file(var.certificate_bundle)))
    error_message = "Supply an existing public certificate bundle containing no private keys."
  }
}
variable "package_repository_file" {
  description = "Local reviewed dnf .repo file; use HTTPS, gpgcheck=1 and approved sources without credentials."
  type        = string
}
variable "package_release" {
  description = "Pinned AL2023 releasever for approved package snapshot, for example 2023.x.YYYYMMDD."
  type        = string
  validation {
    condition     = can(regex("^2023\\.[0-9]+\\.[0-9]{8}$", var.package_release))
    error_message = "Supply an explicit AL2023 package snapshot release."
  }
}
variable "promotion_worker_image" {
  description = "Trusted same-account us-east-2 private ECR worker image pinned by digest; see worker/Dockerfile."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.us-east-2\\.amazonaws\\.com/[a-z0-9/_-]+@sha256:[0-9a-f]{64}$", var.promotion_worker_image))
    error_message = "Supply a trusted private ECR worker digest in us-east-2."
  }
}
variable "schedule_enabled" {
  type        = bool
  default     = false
  description = "Enable weekly builds after the first development acceptance run."
}
variable "scan_timeout_seconds" {
  type        = number
  default     = 3600
  description = "Maximum wait for scan evidence."
}
variable "replication_timeout_seconds" {
  type        = number
  default     = 7200
  description = "Maximum replication wait before blocking catalog release."
}
variable "manage_registry_configuration" {
  type        = bool
  default     = false
  description = "Explicit registry-owner opt-in. Import existing settings and include other rules before setting true."
}
variable "additional_scan_rules" {
  type        = map(list(object({ frequency = string, filters = list(string) })))
  default     = {}
  description = "Existing ENHANCED scan rules keyed by Region, preserved when this stack owns registry configuration."
}
variable "additional_replication_rules" {
  type        = list(object({ destinations = list(object({ region = string, registry_id = string })), prefixes = list(string) }))
  default     = []
  description = "Existing source-registry replication rules to retain when ownership is explicit."
}
variable "tags" {
  type        = map(string)
  default     = {}
  description = "Enterprise ownership and cost allocation tags."
}

variable "access_log_bucket_name" {
  description = "Existing same-account primary-Region S3 server-access-log bucket with delivery permission for the evidence bucket."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.access_log_bucket_name))
    error_message = "Supply the approved S3 access-log bucket name."
  }
}
