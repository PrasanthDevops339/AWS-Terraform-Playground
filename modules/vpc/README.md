# VPC Module

This module creates a Virtual Private Cloud (VPC) with configurable public and private subnets, internet gateway, and optional NAT gateways.

## Features

- VPC with custom CIDR block
- Public and private subnets across multiple availability zones
- Internet Gateway for public subnet internet access
- Optional NAT Gateways for private subnet internet access
- Proper route tables and associations
- Configurable tags

## Usage

```hcl
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["us-west-2a", "us-west-2b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]
  enable_nat_gateway   = true

  tags = {
    Environment = "development"
    Project     = "terraform-playground"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| aws | ~> 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| vpc_cidr | CIDR block for the VPC | `string` | `"10.0.0.0/16"` | no |
| availability_zones | List of availability zones | `list(string)` | `["us-west-2a", "us-west-2b"]` | no |
| public_subnet_cidrs | CIDR blocks for public subnets | `list(string)` | `["10.0.1.0/24", "10.0.2.0/24"]` | no |
| private_subnet_cidrs | CIDR blocks for private subnets | `list(string)` | `["10.0.10.0/24", "10.0.20.0/24"]` | no |
| enable_nat_gateway | Enable NAT Gateway for private subnets | `bool` | `false` | no |
| enable_dns_hostnames | Enable DNS hostnames in the VPC | `bool` | `true` | no |
| enable_dns_support | Enable DNS support in the VPC | `bool` | `true` | no |
| tags | A map of tags to assign to the resource | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | ID of the VPC |
| vpc_cidr_block | CIDR block of the VPC |
| internet_gateway_id | ID of the Internet Gateway |
| public_subnet_ids | List of IDs of the public subnets |
| private_subnet_ids | List of IDs of the private subnets |
| public_subnet_cidrs | List of CIDR blocks of the public subnets |
| private_subnet_cidrs | List of CIDR blocks of the private subnets |
| nat_gateway_ids | List of IDs of the NAT Gateways |
| public_route_table_id | ID of the public route table |
| private_route_table_ids | List of IDs of the private route tables |