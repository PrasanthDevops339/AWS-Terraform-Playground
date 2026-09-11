terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 6.51.0, < 7.0.0" }
  }
}

variable "name" {
  description = "ECR repository name."
  type        = string
}
variable "kms_key_arn" {
  description = "ECR repository kms key arn."
  type        = string
}
variable "organization_id" {
  description = "ECR repository organization id."
  type        = string
}
variable "approved" {
  description = "ECR repository approved."
  type        = bool
}
variable "writer_arns" {
  description = "ECR repository writer arns."
  type        = list(string)
}
variable "reader_arns" {
  description = "ECR repository reader arns."
  type        = list(string)
}

# trivy:ignore:AWS-0030 -- Registry-level enhanced scanning plus a fail-closed release gate replaces the legacy basic flag.
resource "aws_ecr_repository" "this" {
  #checkov:skip=CKV_AWS_163:Enhanced scanning is owned at registry level and enforced by the runtime gate; this legacy check only reads the basic per-repository flag.

  name                 = var.name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }
  lifecycle {
    prevent_destroy = true
  }
}

locals {
  pull_actions  = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
  write_actions = ["ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"]
}

locals {
  repository_policy = jsonencode({ Version = "2012-10-17", Statement = concat([
    { Sid = "OnlyTrustedWriters", Effect = "Deny", Action = local.write_actions, Principal = "*",
    Condition = { ArnNotEquals = { "aws:PrincipalArn" = var.writer_arns } } }
    ], var.approved ? [
    { Sid = "OrganizationPull", Effect = "Allow", Action = local.pull_actions, Principal = { AWS = "*" },
    Condition = { StringEquals = { "aws:PrincipalOrgID" = var.organization_id } } }
    ] : [], var.approved ? [] : [
    { Sid = "PrivateCandidates", Effect = "Deny", Action = local.pull_actions, Principal = "*",
    Condition = { ArnNotEquals = { "aws:PrincipalArn" = var.reader_arns } } }
  ]) })
}

# trivy:ignore:AWS-0032 -- OrganizationPull requires the configured aws:PrincipalOrgID; other wildcard principals occur only in Deny statements.
resource "aws_ecr_repository_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy     = local.repository_policy
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy = jsonencode({ rules = [{
    rulePriority = 1
    description  = var.approved ? "Expire untagged artifacts after 30 days; retain versioned releases" : "Expire candidates after 14 days"
    selection = merge({ tagStatus = var.approved ? "untagged" : "any", countType = "sinceImagePushed", countUnit = "days" },
    { countNumber = var.approved ? 30 : 14 })
    action = { type = "expire" }
  }] })
}

output "arn" {
  description = "ECR repository arn."
  value       = aws_ecr_repository.this.arn
}
output "name" {
  description = "ECR repository name."
  value       = aws_ecr_repository.this.name
}
output "url" {
  description = "ECR repository url."
  value       = aws_ecr_repository.this.repository_url
}
