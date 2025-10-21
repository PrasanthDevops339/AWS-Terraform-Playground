# AWS Service Control Policies (SCP)

This directory contains AWS Service Control Policies (SCPs) for organizational governance.

## Overview

Service Control Policies (SCPs) are a type of organization policy that you can use to manage permissions in your organization. SCPs offer central control over the maximum available permissions for all accounts in your organization.

## Policies

### Block RDS BYOL (Bring Your Own License)

**File:** `block-rds-byol.json`

**Purpose:** This policy prevents the creation and modification of RDS instances that use the "bring-your-own-license" (BYOL) license model.

**Affected Services:**
- Amazon RDS (Relational Database Service)

**Affected Database Engines:**
- Oracle Database (oracle-ee, oracle-se2, oracle-se1, oracle-se)
- Microsoft SQL Server (sqlserver-ee, sqlserver-se, sqlserver-ex, sqlserver-web)

**Blocked Actions:**
- `rds:CreateDBInstance` - Creating new RDS instances with BYOL
- `rds:CreateDBInstanceReadReplica` - Creating read replicas with BYOL
- `rds:RestoreDBInstanceFromDBSnapshot` - Restoring from snapshots with BYOL
- `rds:RestoreDBInstanceFromS3` - Restoring from S3 with BYOL
- `rds:RestoreDBInstanceToPointInTime` - Point-in-time recovery with BYOL
- `rds:ModifyDBInstance` - Modifying instances to use BYOL

**Use Case:**
Use this policy when you want to enforce license-included models only and prevent users from bringing their own licenses for RDS instances. This helps maintain compliance and standardization across your AWS organization.

## How to Apply SCP Policies

1. **Sign in to AWS Organizations console** as the management account

2. **Navigate to Policies** → **Service control policies**

3. **Create a new policy:**
   - Click "Create policy"
   - Give it a descriptive name (e.g., "Block-RDS-BYOL")
   - Copy the JSON content from the respective policy file
   - Create the policy

4. **Attach the policy:**
   - Navigate to the organizational unit (OU) or account
   - Click "Policies" tab
   - Click "Attach" next to Service control policies
   - Select your newly created policy

## Testing

Before applying to production accounts, test the policy in a non-production environment to ensure it doesn't disrupt legitimate operations.

## Policy Structure

All policies follow the standard AWS IAM policy syntax:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "UniqueStatementId",
      "Effect": "Deny|Allow",
      "Action": ["service:Action"],
      "Resource": "*",
      "Condition": {}
    }
  ]
}
```

## Important Notes

- SCPs affect only IAM users and roles in the accounts they're attached to
- SCPs do not affect resource-based policies
- SCPs do not affect the management account (root account)
- Always test SCPs in a non-production environment first
- Use descriptive Sid (Statement IDs) for easier management

## Contributing

When adding new policies:
1. Create a descriptive JSON file name
2. Include comprehensive Sid values
3. Document the policy purpose in this README
4. Test thoroughly before production use

## References

- [AWS Organizations SCPs Documentation](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [RDS License Models](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_BestPractices.Security.html)
