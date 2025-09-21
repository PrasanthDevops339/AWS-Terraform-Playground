# AWS Terraform Playground

A personal repository for learning, experimenting, and developing AWS Terraform modules. This playground contains various Terraform configurations, reusable modules, and examples for AWS infrastructure provisioning.

## 🏗️ Repository Structure

```
.
├── modules/                 # Reusable Terraform modules
│   ├── vpc/                # VPC module
│   ├── ec2/                # EC2 instance module
│   ├── s3/                 # S3 bucket module
│   └── rds/                # RDS database module
├── environments/           # Environment-specific configurations
│   ├── dev/                # Development environment
│   ├── staging/            # Staging environment
│   └── prod/               # Production environment
├── examples/               # Example implementations
└── templates/              # Template files for new modules
```

## 🚀 Getting Started

### Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- An AWS account

### AWS Provider Configuration

Configure your AWS credentials using one of the following methods:

1. **AWS CLI**:
   ```bash
   aws configure
   ```

2. **Environment Variables**:
   ```bash
   export AWS_ACCESS_KEY_ID="your-access-key"
   export AWS_SECRET_ACCESS_KEY="your-secret-key"
   export AWS_DEFAULT_REGION="us-west-2"
   ```

3. **IAM Roles** (recommended for EC2 instances)

## 📚 Available Modules

### VPC Module
Creates a Virtual Private Cloud with configurable subnets, internet gateway, and routing tables.

### EC2 Module
Deploys EC2 instances with customizable configurations including instance type, AMI, security groups, and key pairs.

### S3 Module
Creates S3 buckets with various configurations for different use cases (static websites, data storage, etc.).

### RDS Module
Provisions RDS database instances with proper subnet groups, parameter groups, and security configurations.

## 💡 Usage Examples

### Quick Start
```bash
# Navigate to an example
cd examples/simple-vpc

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### Using Modules
```hcl
module "my_vpc" {
  source = "../../modules/vpc"
  
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["us-west-2a", "us-west-2b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]
  
  tags = {
    Environment = "development"
    Project     = "terraform-playground"
  }
}
```

## 🛠️ Development Guidelines

### Module Structure
Each module should follow this structure:
```
module_name/
├── main.tf          # Main configuration
├── variables.tf     # Input variables
├── outputs.tf       # Output values
├── versions.tf      # Terraform and provider version constraints
└── README.md        # Module documentation
```

### Best Practices
- Use consistent naming conventions
- Always include proper variable descriptions
- Define appropriate output values
- Include example usage in module README
- Use data sources when possible instead of hardcoding values
- Tag all resources appropriately

## 📝 Contributing

This is a personal learning repository, but suggestions and improvements are welcome:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 🔧 Useful Commands

```bash
# Format Terraform files
terraform fmt -recursive

# Validate configuration
terraform validate

# Check for security issues (requires tfsec)
tfsec .

# Generate dependency graph
terraform graph | dot -Tpng > graph.png
```

## 📖 Learning Resources

- [Terraform Documentation](https://www.terraform.io/docs/)
- [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

## ⚠️ Important Notes

- This repository is for learning and experimentation
- Always review costs before applying configurations
- Use appropriate AWS regions for your use case
- Remember to destroy resources when not needed: `terraform destroy`
- Never commit sensitive information like access keys or passwords

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.