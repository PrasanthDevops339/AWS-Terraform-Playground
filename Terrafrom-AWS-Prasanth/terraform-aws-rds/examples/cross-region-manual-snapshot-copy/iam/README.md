# 📂 IAM Policy & KMS Key Statements File Structure

## 🎯 **Overview**

Following the terraform-aws-lambda module's complete example pattern, all IAM policies and KMS key statements have been moved to separate JSON files for better organization and maintainability.

## 📋 **File Structure**

```
├── iam/
│   ├── lambda-rds-policy.json              # Lambda IAM policy JSON file
│   ├── primary-kms-key-statements.json     # Primary region KMS key statements
│   ├── secondary-kms-key-statements.json   # Secondary region KMS key statements
│   └── README.md                           # This documentation
├── lambda/
│   └── lambda_function.py                  # Lambda function code
├── main.tf                                 # Main Terraform configuration
└── variables.tf                            # Input variables
```

## 🔧 **How It Works**

### **1. Lambda IAM Policy**: `iam/lambda-rds-policy.json`
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBInstances",
        "rds:DescribeDBSnapshots",
        // ... more RDS permissions
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey*",
        // ... more KMS permissions
      ],
      "Resource": [
        "${PRIMARY_KMS_KEY_ARN}",
        "${SECONDARY_KMS_KEY_ARN}"
      ]
    }
  ]
}
```

### **2. Primary KMS Key Statements**: `iam/primary-kms-key-statements.json`
```json
[
  {
    "sid": "EnableIAMUserPermissions",
    "effect": "Allow",
    "principals": [{"type": "AWS", "identifiers": ["..."]}],
    "actions": ["kms:Decrypt", "kms:GenerateDataKey*", "..."]
  },
  {
    "sid": "AllowRDSService", 
    "effect": "Allow",
    "principals": [{"type": "Service", "identifiers": ["rds.amazonaws.com"]}]
  },
  {
    "sid": "AllowLambdaService",
    "effect": "Allow", 
    "principals": [{"type": "Service", "identifiers": ["lambda.amazonaws.com"]}]
  }
]
```

### **3. Secondary KMS Key Statements**: `iam/secondary-kms-key-statements.json`
```json
[
  {
    "sid": "EnableIAMUserPermissions",
    "effect": "Allow",
    "principals": [{"type": "AWS", "identifiers": ["..."]}]
  },
  {
    "sid": "AllowRDSService",
    "effect": "Allow", 
    "principals": [{"type": "Service", "identifiers": ["rds.amazonaws.com"]}]
  },
  {
    "sid": "AllowCrossRegionBackup",
    "effect": "Allow",
    "principals": [{"type": "AWS", "identifiers": ["${LAMBDA_EXECUTION_ROLE_ARN}"]}]
  }
]
```

### **4. Template Data Sources**: `main.tf`
```hcl
# Primary KMS key statements
data "template_file" "primary_kms_key_statements" {
  template = file("${path.module}/iam/primary-kms-key-statements.json")
  vars = {
    ACCOUNT_ID     = var.account_id
    ACCOUNT_ALIAS  = data.aws_iam_account_alias.current.account_alias
    PRIMARY_REGION = var.primary_region
  }
}

# Secondary KMS key statements  
data "template_file" "secondary_kms_key_statements" {
  template = file("${path.module}/iam/secondary-kms-key-statements.json")
  vars = {
    ACCOUNT_ID                = var.account_id
    ACCOUNT_ALIAS             = data.aws_iam_account_alias.current.account_alias
    PRIMARY_REGION            = var.primary_region
    SECONDARY_REGION          = var.secondary_region
    LAMBDA_EXECUTION_ROLE_ARN = aws_iam_role.lambda_execution_role.arn
  }
}

# Lambda RDS policy
data "template_file" "lambda_rds_policy" {
  template = file("${path.module}/iam/lambda-rds-policy.json")
  vars = {
    PRIMARY_KMS_KEY_ARN   = module.primary_kms.key_arn
    SECONDARY_KMS_KEY_ARN = module.secondary_kms.key_arn
  }
}
```

### **5. Resource Usage**: `main.tf`
```hcl
# Primary KMS module
module "primary_kms" {
  key_statements = jsondecode(data.template_file.primary_kms_key_statements.rendered)
}

# Secondary KMS module  
module "secondary_kms" {
  key_statements = jsondecode(data.template_file.secondary_kms_key_statements.rendered)
}

# Lambda IAM role policy
resource "aws_iam_role_policy" "lambda_rds_policy" {
  name   = "${local.resource_names.lambda_role}-rds-policy"
  role   = aws_iam_role.lambda_execution_role.id
  policy = data.template_file.lambda_rds_policy.rendered
}
```

## ✅ **Benefits of This Approach**

### **1. 📂 Better Organization**
- **Complete Separation**: All IAM policies and KMS statements in dedicated files
- **Cleaner main.tf**: Significantly reduced inline JSON in main Terraform file
- **Modular Structure**: Easy to find, modify, and audit specific policy components
- **Consistent Pattern**: All policies follow the same external JSON file pattern

### **2. 🔧 Enhanced Maintainability**
- **JSON Validation**: Proper JSON syntax highlighting and validation in IDEs
- **Version Control**: Better diff tracking for policy and KMS statement changes
- **Reusability**: Policies can be easily copied to other projects
- **Template Variables**: Dynamic substitution for environment-specific values

### **3. 🎯 Advanced Variable Substitution**
- **Lambda Policy**: KMS key ARNs dynamically injected
- **KMS Policies**: Account ID, regions, and role ARNs dynamically substituted
- **Environment Flexibility**: Same templates work across different environments
- **Template Processing**: Terraform processes all variables at plan/apply time

### **4. 📋 Enhanced Compliance & Auditing**
- **Clear Separation**: IAM and KMS permissions are easily reviewable in isolation
- **Security Review**: Security teams can audit all policy files independently
- **Documentation**: Policy permissions and KMS statements are self-documenting
- **Change Tracking**: Git history clearly shows policy vs infrastructure changes

## 🔄 **How Variable Substitution Works**

### **Lambda IAM Policy Variables**
1. **Template Loading**: `file()` loads `lambda-rds-policy.json`
2. **Variable Injection**: 
   - `${PRIMARY_KMS_KEY_ARN}` → `module.primary_kms.key_arn`
   - `${SECONDARY_KMS_KEY_ARN}` → `module.secondary_kms.key_arn`
3. **Policy Rendering**: `.rendered` provides final policy JSON
4. **IAM Application**: Rendered policy attached to Lambda execution role

### **KMS Key Statement Variables**
1. **Primary KMS Variables**:
   - `${ACCOUNT_ID}` → `var.account_id`
   - `${ACCOUNT_ALIAS}` → `data.aws_iam_account_alias.current.account_alias`
   - `${PRIMARY_REGION}` → `var.primary_region`

2. **Secondary KMS Variables**:
   - All primary variables PLUS:
   - `${SECONDARY_REGION}` → `var.secondary_region`
   - `${LAMBDA_EXECUTION_ROLE_ARN}` → `aws_iam_role.lambda_execution_role.arn`

3. **KMS Processing**: 
   - `jsondecode()` converts rendered JSON strings to Terraform objects
   - KMS modules consume the structured data directly

## 🎉 **Result**

All IAM policies and KMS key statements are now externalized with identical functionality:

### **✅ Lambda IAM Policy**
- **Organized** in separate JSON file
- **Maintainable** with proper JSON formatting
- **Dynamic** KMS key ARN substitution

### **✅ KMS Key Statements**  
- **Primary KMS**: Admin permissions, RDS service access, Lambda service access
- **Secondary KMS**: Admin permissions, RDS service access, cross-region backup access
- **Flexible** variable substitution for account, regions, and role ARNs

### **✅ Infrastructure Benefits**
- **Cleaner main.tf**: No more inline JSON policy blocks
- **Professional Structure**: Follows terraform-aws-lambda module best practices
- **Audit Ready**: Security teams can easily review all policies in `iam/` directory
- **Version Control**: Better diff tracking for policy changes
- **Reusable**: Policy templates can be copied to other projects

This matches the enterprise pattern used in the terraform-aws-lambda module's complete example! 🚀