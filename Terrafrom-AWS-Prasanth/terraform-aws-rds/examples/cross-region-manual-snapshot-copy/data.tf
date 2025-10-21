################################################################################
# Data Sources - Cross-Region Manual Snapshot Copy
# Following AWS Well-Architected Framework principles for data retrieval
################################################################################

#------------------------------------------------------------------------------
# ACCOUNT AND IDENTITY INFORMATION
#------------------------------------------------------------------------------

# AWS account information for IAM policies and resource ARNs
data "aws_caller_identity" "current" {
  provider = aws.primary
}

# Account alias for consistent resource naming
data "aws_iam_account_alias" "current" {
  provider = aws.primary
}

#------------------------------------------------------------------------------
# PRIMARY REGION DATA SOURCES (us-east-2)
#------------------------------------------------------------------------------

# Primary VPC - using configurable name for flexibility
data "aws_vpc" "primary" {
  provider = aws.primary

  filter {
    name   = "tag:Name"
    values = [var.primary_vpc_name]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Primary region private subnets for RDS deployment (multi-AZ)
data "aws_subnets" "primary" {
  provider = aws.primary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  filter {
    name   = "tag:Type"
    values = ["private", "Private"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Primary region availability zones for Multi-AZ deployment
data "aws_availability_zones" "primary" {
  provider = aws.primary
  state    = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

#------------------------------------------------------------------------------
# SECONDARY REGION DATA SOURCES (us-east-1) - DISASTER RECOVERY
#------------------------------------------------------------------------------

# Secondary VPC - using configurable name for flexibility
data "aws_vpc" "secondary" {
  provider = aws.secondary

  filter {
    name   = "tag:Name"
    values = [var.secondary_vpc_name]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Secondary region private subnets for disaster recovery deployment
data "aws_subnets" "secondary" {
  provider = aws.secondary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }

  filter {
    name   = "tag:Type"
    values = ["private", "Private"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Secondary region availability zones for disaster recovery
data "aws_availability_zones" "secondary" {
  provider = aws.secondary
  state    = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

#------------------------------------------------------------------------------
# VALIDATION DATA SOURCES
#------------------------------------------------------------------------------

# Validate that we have sufficient subnets in primary region for Multi-AZ
locals {
  primary_subnet_count   = length(data.aws_subnets.primary.ids)
  secondary_subnet_count = length(data.aws_subnets.secondary.ids)

  # Validation checks
  validation_checks = {
    primary_subnets_sufficient   = local.primary_subnet_count >= 2
    secondary_subnets_sufficient = local.secondary_subnet_count >= 2
    regions_are_different        = var.primary_region != var.secondary_region
  }
}