# Simple VPC Example

This example demonstrates how to create a basic VPC using the VPC module.

## What This Example Creates

- A VPC with CIDR block 10.0.0.0/16
- Two public subnets in different availability zones
- Two private subnets in different availability zones
- An Internet Gateway for public subnet internet access
- Proper route tables and associations

Note: NAT gateways are disabled by default to avoid costs. Set `enable_nat_gateway = true` if you need private subnet internet access.

## Usage

1. Navigate to this directory:
   ```bash
   cd examples/simple-vpc
   ```

2. Initialize Terraform:
   ```bash
   terraform init
   ```

3. Review the plan:
   ```bash
   terraform plan
   ```

4. Apply the configuration:
   ```bash
   terraform apply
   ```

5. When done, destroy the resources:
   ```bash
   terraform destroy
   ```

## Customization

You can customize the configuration by modifying the variables in `variables.tf` or creating a `terraform.tfvars` file:

```hcl
aws_region   = "us-east-1"
environment  = "production"
project_name = "my-project"
```

## Outputs

After applying, you'll get:
- VPC ID
- Public subnet IDs
- Private subnet IDs

These outputs can be used by other Terraform configurations to deploy resources into this VPC.