# AWS Service Control Policies (SCPs)

## 📋 Overview

This directory contains Service Control Policies (SCPs) for governance and compliance across AWS Organizations. These policies enforce security best practices, cost controls, and operational standards.

## 🔐 Available Policies

### 1. **EBS Governance Policy** ([ebs-governance.json](ebs-governance.json))

Enforces security and operational standards for Amazon EBS volumes.

**Protections:**
- ✅ **Encryption Enforcement**: Denies creation of unencrypted EBS volumes
- ✅ **Tagging Requirements**: Requires `Environment` tag on all volumes
- ✅ **Deletion Protection**: Prevents deletion of volumes tagged with `DeletionProtection: true`
- ✅ **Volume Type Restrictions**: Limits to approved types (gp3, gp2, io2, io1)

**Denied Actions:**
```json
- ec2:CreateVolume (if unencrypted or untagged)
- ec2:RunInstances (if launching with unencrypted volumes)
- ec2:DeleteVolume (if deletion protection enabled)
- ec2:ModifyVolume (if changing to unapproved type)
```

**Use Cases:**
- Enforce encryption at rest compliance
- Prevent accidental data exposure
- Control EBS costs by limiting volume types
- Protect production volumes from deletion

---

### 2. **SQS Governance Policy** ([sqs-governance.json](sqs-governance.json))

Enforces security and operational standards for Amazon SQS queues.

**Protections:**
- ✅ **Encryption Enforcement**: Requires KMS encryption for all queues
- ✅ **Tagging Requirements**: Requires `Environment` tag on queue creation
- ✅ **Public Access Prevention**: Blocks queues with wildcard principal (`*`)
- ✅ **Deletion Protection**: Prevents deletion of protected queues
- ✅ **Retention Limits**: Enforces max 14-day message retention

**Denied Actions:**
```json
- sqs:CreateQueue (if unencrypted, untagged, or excessive retention)
- sqs:AddPermission (if granting public access)
- sqs:SetQueueAttributes (if setting public access)
- sqs:DeleteQueue (if deletion protection enabled)
```

**Use Cases:**
- Protect sensitive message data with encryption
