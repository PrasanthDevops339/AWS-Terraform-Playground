# Requirements Document

## Introduction

This document specifies the requirements for implementing AMI (Amazon Machine Image) governance controls for AWS Organizations. The system enforces that EC2 instances can only be launched using approved AMIs from designated publisher accounts, using AWS Organizations declarative policies as the primary control mechanism and Service Control Policies (SCPs) as a secondary defense layer.

The solution addresses the need for centralized AMI governance across multiple AWS accounts within an organization, ensuring security, compliance, and operational consistency while providing a time-bound exception process for legitimate use cases.

## Glossary

- **AMI_Governance_System**: The complete solution including declarative policies, SCPs, and Terraform infrastructure
- **Declarative_Policy**: AWS Organizations policy type that enforces EC2 account-attribute configuration at the service control plane level
- **SCP**: Service Control Policy - IAM-based permission boundary that acts as a secondary enforcement layer
- **Golden_AMI**: Approved, hardened AMI created by the Operations team following security and compliance standards
- **Publisher_Account**: AWS account authorized to create and share AMIs for use across the organization
- **Exception_Account**: AWS account temporarily granted permission to use non-standard AMIs with a defined expiry date (maximum 365 days for exception AMIs, 90 days for other exceptions)
- **Enforcement_Mode**: Configuration state controlling whether violations are logged only (audit_mode) or actively blocked (enabled)
- **Target_ID**: AWS Organizations identifier for Root, Organizational Unit (OU), or Account where policies are attached
- **Allowlist**: Complete set of approved AMI publisher account IDs including operations, vendors, and active exceptions

## Requirements

### Requirement 1: Golden AMI Publisher Control

**User Story:** As a Cloud Security Engineer, I want to designate specific accounts as approved AMI publishers, so that only vetted and hardened AMIs can be used across the organization.

#### Acceptance Criteria

1. THE AMI_Governance_System SHALL designate account 565656565656 (prasains-operations-dev-use2) as an approved publisher
2. THE AMI_Governance_System SHALL designate account 666363636363 (prasains-operations-prd-use2) as an approved publisher
3. WHEN an EC2 instance launch uses an AMI from an approved publisher account, THE AMI_Governance_System SHALL allow the launch
4. WHEN an EC2 instance launch uses an AMI not from an approved publisher account, THE AMI_Governance_System SHALL deny the launch
5. THE AMI_Governance_System SHALL support AMI name patterns: prasa-rhel8-*, prasa-rhel9-*, prasa-win16-*, prasa-win19-*, prasa-win22-*, prasa-al2023-*, prasa-al2-2024-*, prasa-mlal2-*, prasa-opsdir-mlal2-*

### Requirement 2: Vendor AMI Publisher Support

**User Story:** As a Platform Engineer, I want to allow specific third-party vendor accounts to publish AMIs, so that we can use approved commercial software and appliances.

#### Acceptance Criteria

1. THE AMI_Governance_System SHALL maintain a configurable list of approved vendor publisher accounts
2. WHEN a vendor account is added to the approved list, THE AMI_Governance_System SHALL include it in the allowlist
3. WHEN an EC2 instance launch uses an AMI from an approved vendor account, THE AMI_Governance_System SHALL allow the launch
4. THE AMI_Governance_System SHALL support multiple vendor accounts simultaneously

### Requirement 3: Time-Bound Exception Management

**User Story:** As a Cloud Operations Manager, I want to grant temporary exceptions for specific accounts to use non-standard AMIs, so that migration projects and special workloads can proceed with defined time limits.

#### Acceptance Criteria

1. WHEN an exception is created for an account, THE AMI_Governance_System SHALL require an expiry date in YYYY-MM-DD format
2. WHEN the current date is before the exception expiry date, THE AMI_Governance_System SHALL include the exception account in the allowlist
3. WHEN the current date is on or after the exception expiry date, THE AMI_Governance_System SHALL exclude the exception account from the allowlist
4. WHEN Terraform apply is executed with expired exceptions, THE AMI_Governance_System SHALL fail the deployment with an error message listing expired exceptions
5. THE AMI_Governance_System SHALL automatically filter active exceptions without manual intervention
6. WHEN an exception account is in the allowlist, THE AMI_Governance_System SHALL allow EC2 launches using AMIs from that account

### Requirement 4: Dual-Layer Enforcement Architecture

**User Story:** As a Security Architect, I want both declarative policies and SCPs enforcing AMI restrictions, so that we have defense-in-depth with no single point of failure.

#### Acceptance Criteria

1. THE AMI_Governance_System SHALL create an AWS Organizations declarative policy of type DECLARATIVE_POLICY_EC2
2. THE AMI_Governance_System SHALL create a Service Control Policy (SCP) with IAM-based restrictions
3. WHEN the declarative policy is bypassed or fails, THE SCP SHALL still block non-compliant EC2 launches
4. THE Declarative_Policy SHALL enforce allowed AMI publishers at the EC2 service control plane level
5. THE SCP SHALL deny ec2:RunInstances, ec2:CreateFleet, ec2:RequestSpotInstances, and ec2:RunScheduledInstances when AMI owner is not in the allowlist
6. THE SCP SHALL deny ec2:CreateImage, ec2:CopyImage, ec2:RegisterImage, and ec2:ImportImage to prevent AMI side-loading
7. THE SCP SHALL deny ec2:ModifyImageAttribute when adding public launch permissions (group = all)

### Requirement 5: Enforcement Mode Control

**User Story:** As a Cloud Platform Engineer, I want to test AMI governance in audit mode before full enforcement, so that I can identify impacted workloads without causing outages.

#### Acceptance Criteria

1. THE AMI_Governance_System SHALL support two enforcement modes: audit_mode and enabled
2. WHEN enforcement_mode is set to audit_mode, THE Declarative_Policy SHALL log violations without blocking EC2 launches
3. WHEN enforcement_mode is set to enabled, THE Declarative_Policy SHALL block non-compliant EC2 launches
4. WHEN enforcement_mode is audit_mode, THE AMI_Governance_System SHALL include imageAllowed indicators in DescribeImages API responses
5. THE AMI_Governance_System SHALL allow switching from audit_mode to enabled without recreating policies
6. THE SCP SHALL enforce restrictions regardless of enforcement_mode setting

### Requirement 6: Public AMI Sharing Prevention

**User Story:** As a Security Engineer, I want to prevent accounts from making AMIs publicly accessible, so that we avoid data exfiltration and unauthorized access to our custom images.

#### Acceptance Criteria

1. THE Declarative_Policy SHALL set image_block_public_access state to block_new_sharing
2. WHEN an account attempts to make an AMI publicly accessible, THE AMI_Governance_System SHALL deny the action
3. WHEN an AMI is already publicly shared before policy enforcement, THE AMI_Governance_System SHALL allow it to remain public
4. THE SCP SHALL deny ec2:ModifyImageAttribute when the condition ec2:Add/group equals all

### Requirement 7: Policy Attachment and Scope

**User Story:** As an AWS Organizations Administrator, I want to attach AMI governance policies to specific organizational units or the root, so that I can control the scope of enforcement.

#### Acceptance Criteria

1. THE AMI_Governance_System SHALL accept a list of Target_IDs for policy attachment
2. WHEN a Target_ID is an Organization Root ID, THE AMI_Governance_System SHALL attach policies to the entire organization
3. WHEN a Target_ID is an OU ID, THE AMI_Governance_System SHALL attach policies to that OU and its child accounts
4. WHEN a Target_ID is an Account ID, THE AMI_Governance_System SHALL attach policies to that specific account
5. THE AMI_Governance_System SHALL attach both the Declarative_Policy and SCP to each Target_ID
6. THE AMI_Governance_System SHALL prevent child OUs and accounts from overriding policy settings using @@operators_allowed_for_child_policies set to @@none

### Requirement 8: User-Friendly Error Messages

**User Story:** As a Developer, I want clear error messages when my EC2 launch is blocked, so that I understand why it failed and how to request an exception.

#### Acceptance Criteria

1. THE Declarative_Policy SHALL include a custom exception_message field
2. WHEN an EC2 launch is blocked by the Declarative_Policy, THE AMI_Governance_System SHALL display the custom exception message
3. THE exception_message SHALL list approved AMI name patterns
4. THE exception_message SHALL list approved publisher account IDs and their aliases
5. THE exception_message SHALL include a URL for submitting exception requests
6. THE exception_message SHALL specify the maximum exception duration (365 days for exception AMIs, 90 days for other exceptions)

### Requirement 9: Infrastructure as Code Deployment

**User Story:** As a DevOps Engineer, I want to deploy AMI governance using Terraform, so that changes are version-controlled, auditable, and repeatable.

#### Acceptance Criteria

1. THE AMI_Governance_System SHALL be implemented using Terraform with version >= 1.0
2. THE AMI_Governance_System SHALL use AWS provider version >= 5.0 for DECLARATIVE_POLICY_EC2 support
3. THE AMI_Governance_System SHALL use aws_organizations_policy resource for policy creation
4. THE AMI_Governance_System SHALL use aws_organizations_policy_attachment resource for policy attachment
5. THE AMI_Governance_System SHALL organize code into reusable modules under modules/ami-governance/
6. THE AMI_Governance_System SHALL organize environment-specific configurations under environments/prd/ and environments/dev/
7. WHEN Terraform apply is executed, THE AMI_Governance_System SHALL create or update both declarative policy and SCP
8. WHEN Terraform apply is executed, THE AMI_Governance_System SHALL attach policies to all specified Target_IDs

### Requirement 10: Allowlist Construction and Sorting

**User Story:** As a Platform Engineer, I want the system to automatically build and sort the AMI publisher allowlist, so that policy updates are deterministic and easy to review.

#### Acceptance Criteria

1. THE AMI_Governance_System SHALL combine ops_publisher_account, vendor_publisher_accounts, and active exception accounts into a single allowlist
2. THE AMI_Governance_System SHALL sort the allowlist alphabetically by account ID
3. WHEN the allowlist changes, THE AMI_Governance_System SHALL update both the Declarative_Policy and SCP with the new allowlist
4. THE AMI_Governance_System SHALL use the same allowlist for both Declarative_Policy image_criteria and SCP ec2:Owner condition

### Requirement 11: Policy Validation and Effective Policy Checking

**User Story:** As a Cloud Security Engineer, I want to validate the effective policy on target accounts, so that I can confirm inheritance and enforcement before production rollout.

#### Acceptance Criteria

1. THE AMI_Governance_System SHALL support AWS CLI command describe-effective-policy for validation
2. WHEN describe-effective-policy is executed for a target account, THE AMI_Governance_System SHALL return the combined inherited and directly attached policies
3. THE AMI_Governance_System SHALL document the validation process in deployment guides
4. WHEN policies are attached to multiple levels (Root, OU, Account), THE effective policy SHALL reflect the most restrictive settings

### Requirement 12: Phased Rollout Support

**User Story:** As a Cloud Operations Manager, I want to roll out AMI governance in phases, so that I can validate with pilot accounts before organization-wide enforcement.

#### Acceptance Criteria

1. THE AMI_Governance_System SHALL support attaching policies to a subset of OUs or accounts initially
2. WHEN policies are attached to a pilot OU, THE AMI_Governance_System SHALL not affect other OUs
3. THE AMI_Governance_System SHALL allow expanding policy attachment to additional Target_IDs without disrupting existing attachments
4. THE AMI_Governance_System SHALL support starting with audit_mode in pilot phase and switching to enabled in production phase

### Requirement 13: CloudTrail Logging and Monitoring

**User Story:** As a Security Analyst, I want all AMI governance policy evaluations logged to CloudTrail, so that I can audit compliance and investigate violations.

#### Acceptance Criteria

1. WHEN the Declarative_Policy evaluates an EC2 launch, THE AMI_Governance_System SHALL log the evaluation to CloudTrail
2. WHEN enforcement_mode is audit_mode, THE CloudTrail logs SHALL include imageAllowed indicators for non-compliant AMIs
3. WHEN enforcement_mode is enabled, THE CloudTrail logs SHALL include AccessDenied events for blocked launches
4. THE CloudTrail logs SHALL include the policy ID and evaluation result
5. THE CloudTrail logs SHALL be queryable using aws cloudtrail lookup-events with EventName=RunInstances

### Requirement 14: Resource Tagging

**User Story:** As a Cloud Financial Analyst, I want all AMI governance policies tagged with metadata, so that I can track ownership, cost allocation, and management responsibility.

#### Acceptance Criteria

1. THE AMI_Governance_System SHALL apply tags to all created policies
2. THE AMI_Governance_System SHALL include a ManagedBy tag with value Terraform
3. THE AMI_Governance_System SHALL include an Environment tag indicating dev or prd
4. THE AMI_Governance_System SHALL include a PolicyType tag indicating DECLARATIVE_POLICY_EC2 or SERVICE_CONTROL_POLICY
5. THE AMI_Governance_System SHALL support custom tags provided via the tags variable
6. THE AMI_Governance_System SHALL merge custom tags with default tags

### Requirement 15: Exception Request Process Documentation

**User Story:** As a Developer, I want clear documentation on how to request AMI exceptions, so that I can get approval for legitimate special cases.

#### Acceptance Criteria

1. THE AMI_Governance_System SHALL document the exception request process
2. THE exception request process SHALL require business justification
3. THE exception request process SHALL require security approval
4. THE exception request process SHALL specify maximum exception duration of 365 days for exception AMIs
5. THE exception request process SHALL specify maximum exception duration of 90 days for other exception types
6. THE exception request process SHALL include the Jira ticket URL for submissions
7. THE exception request process SHALL define who approves exceptions (Cloud Platform Team)

### Requirement 16: Terraform State Management

**User Story:** As a DevOps Engineer, I want Terraform to track the state of all AMI governance resources, so that I can safely update and destroy policies without orphaning resources.

#### Acceptance Criteria

1. THE AMI_Governance_System SHALL store policy IDs in Terraform state
2. THE AMI_Governance_System SHALL store policy attachment IDs in Terraform state
3. WHEN a Target_ID is removed from the configuration, THE AMI_Governance_System SHALL detach the policy from that target
4. WHEN an exception account is removed from the configuration, THE AMI_Governance_System SHALL update the allowlist and policies
5. THE AMI_Governance_System SHALL support terraform destroy to remove all policies and attachments

### Requirement 17: Expired Exception Detection and Blocking

**User Story:** As a Security Engineer, I want Terraform to fail if expired exceptions exist in the configuration, so that we maintain strict time-bound exception enforcement.

#### Acceptance Criteria

1. THE AMI_Governance_System SHALL calculate the current date at Terraform execution time
2. THE AMI_Governance_System SHALL compare each exception expiry date to the current date
3. WHEN an exception expiry date is in the past, THE AMI_Governance_System SHALL add it to the expired_exceptions list
4. WHEN expired_exceptions list is not empty, THE AMI_Governance_System SHALL fail terraform apply with exit code 1
5. THE error message SHALL list each expired exception with account ID and expiry date
6. THE error message SHALL instruct the user to remove expired exceptions from configuration
7. THE AMI_Governance_System SHALL use a null_resource with local-exec provisioner for validation

### Requirement 18: Module Reusability

**User Story:** As a Platform Engineer, I want the AMI governance module to be reusable across environments, so that I can deploy consistent policies to dev and production with different configurations.

#### Acceptance Criteria

1. THE AMI_Governance_System SHALL implement a reusable Terraform module under modules/ami-governance/
2. THE module SHALL accept input variables for all configurable parameters
3. THE module SHALL output approved_ami_owners list
4. THE module SHALL output policy_summary information
5. THE module SHALL output expired_exceptions list
6. THE module SHALL be invocable from multiple environment directories (environments/dev/, environments/prd/)
7. WHEN the module is invoked with different variables, THE AMI_Governance_System SHALL create environment-specific policies

### Requirement 19: Policy Naming Convention

**User Story:** As an AWS Administrator, I want policies named clearly with environment indicators, so that I can distinguish dev and production policies in the AWS console.

#### Acceptance Criteria

1. THE AMI_Governance_System SHALL accept declarative_policy_name as a variable
2. THE AMI_Governance_System SHALL accept scp_policy_name as a variable
3. THE default declarative policy name SHALL be ami-governance-declarative-policy
4. THE default SCP name SHALL be scp-ami-guardrail
5. WHEN environment is prd, THE policy names SHALL include -prd suffix
6. WHEN environment is dev, THE policy names SHALL include -dev suffix

### Requirement 20: AWS Provider Configuration

**User Story:** As a DevOps Engineer, I want the Terraform configuration to specify required provider versions, so that deployments fail fast if incompatible versions are used.

#### Acceptance Criteria

1. THE AMI_Governance_System SHALL require Terraform version >= 1.0
2. THE AMI_Governance_System SHALL require AWS provider version >= 5.0
3. THE AMI_Governance_System SHALL require null provider version >= 3.0
4. WHEN an incompatible provider version is used, THE Terraform init SHALL fail with a clear error message
5. THE AMI_Governance_System SHALL configure the AWS provider with a default region variable
