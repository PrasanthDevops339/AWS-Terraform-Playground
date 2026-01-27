# Architecture Overview

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          AWS Organization                                │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │              Organization Conformance Pack                       │   │
│  │                 (encryption-validation)                          │   │
│  │                                                                   │   │
│  │  ┌──────────────────────────────────────────────────────────┐  │   │
│  │  │            Guard Policy Rules (Custom Policy)             │  │   │
│  │  │                                                            │  │   │
│  │  │  • ebs-is-encrypted                                       │  │   │
│  │  │    └─> Validates: AWS::EC2::Volume, AWS::EC2::Snapshot   │  │   │
│  │  │                                                            │  │   │
│  │  │  • sqs-is-encrypted                                       │  │   │
│  │  │    └─> Validates: AWS::SQS::Queue                        │  │   │
│  │  │                                                            │  │   │
│  │  │  • efs-is-encrypted                                       │  │   │
│  │  │    └─> Validates: AWS::EFS::FileSystem                   │  │   │
│  │  └──────────────────────────────────────────────────────────┘  │   │
│  │                                                                   │   │
│  │  ┌──────────────────────────────────────────────────────────┐  │   │
│  │  │           Lambda Custom Rules                             │  │   │
│  │  │                                                            │  │   │
│  │  │  • efs-tls-enforcement                                    │  │   │
│  │  │    └─> Validates: AWS::EFS::FileSystem                   │  │   │
│  │  │    └─> Lambda ARN: module.efs_tls_enforcement.lambda_arn │  │   │
│  │  └──────────────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                           │
│  Deployed to:                                                            │
│  • us-east-2 (Primary)                                                   │
│  • us-east-1 (Secondary)                                                 │
│                                                                           │
│  Excluded Accounts:                                                      │
│  • Sandbox/Test accounts (documented)                                    │
└─────────────────────────────────────────────────────────────────────────┘
```

## Lambda Custom Rule Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                     EFS TLS Enforcement Flow                        │
└────────────────────────────────────────────────────────────────────┘

    ┌──────────────────┐
    │  EFS FileSystem  │  ──┐
    │   Configuration  │    │
    │     Change       │    │
    └──────────────────┘    │
                            │ 1. Config Change Notification
                            ▼
    ┌──────────────────────────────────────┐
    │         AWS Config Service           │
    │                                      │
    │  • Detects resource changes          │
    │  • Scoped to: AWS::EFS::FileSystem  │
    │  • Triggers: ConfigurationItem...   │
    └──────────────────────────────────────┘
                            │
                            │ 2. Invoke Lambda
                            ▼
    ┌──────────────────────────────────────┐
    │       Lambda Function                │
    │   efs-tls-enforcement                │
    │                                      │
    │  Runtime: Python 3.12                │
    │  Timeout: 30 seconds                 │
    │  Memory: 128 MB                      │
    └──────────────────────────────────────┘
                            │
                            │ 3. DescribeFileSystemPolicy
                            ▼
    ┌──────────────────────────────────────┐
    │      Amazon EFS Service              │
    │                                      │
    │  API: DescribeFileSystemPolicy       │
    └──────────────────────────────────────┘
                            │
                            │ 4. Return Policy JSON
                            ▼
    ┌──────────────────────────────────────┐
    │       Lambda Function                │
    │   Policy Evaluation Logic            │
    │                                      │
    │  ✓ Check for aws:SecureTransport    │
    │  ✓ Validate Deny statement          │
    │  ✓ Determine compliance              │
    └──────────────────────────────────────┘
                            │
                            │ 5. PutEvaluations
                            ▼
    ┌──────────────────────────────────────┐
    │         AWS Config Service           │
    │                                      │
    │  Compliance States:                  │
    │  • COMPLIANT                         │
    │  • NON_COMPLIANT                     │
    │  • NOT_APPLICABLE                    │
    └──────────────────────────────────────┘
                            │
                            │ 6. Store Results
                            ▼
    ┌──────────────────────────────────────┐
    │      Config Compliance Data          │
    │                                      │
    │  • Compliance history                │
    │  • Annotations                       │
    │  • Timestamps                        │
    └──────────────────────────────────────┘
```

## IAM Permissions Flow

```
┌────────────────────────────────────────────────────────────────────┐
│                    Lambda Execution Role                            │
│                   efs-tls-enforcement-role                         │
└────────────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┴───────────────────┐
        │                                       │
        ▼                                       ▼
┌──────────────────┐                   ┌──────────────────┐
│   Base Policy    │                   │  Custom Policy   │
│  (Inline)        │                   │    (Inline)      │
│                  │                   │                  │
│ • CloudWatch     │                   │ • EFS Describe   │
│   Logs           │                   │   Permissions    │
│ • Config Put     │                   │                  │
│   Evaluations    │                   │                  │
└──────────────────┘                   └──────────────────┘

Permissions Details:

Base Policy (lambda_policy.json):
  ✓ logs:CreateLogGroup
  ✓ logs:CreateLogStream
  ✓ logs:PutLogEvents
  ✓ logs:DescribeLogStreams
  ✓ config:PutEvaluations

Custom Policy (efs-tls-enforcement.json):
  ✓ elasticfilesystem:DescribeFileSystemPolicy
  ✓ elasticfilesystem:DescribeFileSystems
```

## Terraform Module Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                   Terraform Root Module                          │
│                  environments/prd/                               │
└─────────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│   Lambda     │   │ Conformance  │   │   Policy     │
│   Rule       │   │    Pack      │   │    Rule      │
│   Module     │   │   Module     │   │   Module     │
└──────────────┘   └──────────────┘   └──────────────┘
        │                   │                   │
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│ • Lambda     │   │ • Org Pack   │   │ • Org Rule   │
│ • IAM Role   │   │ • Template   │   │ • Guard      │
│ • Permission │   │ • Variables  │   │   Policy     │
└──────────────┘   └──────────────┘   └──────────────┘

Dependencies:
  Lambda Rule ──┬─> Conformance Pack (lambda_rules_list)
                │
  Policy Rule ──┴─> Conformance Pack (policy_rules_list)
  
  Managed Rules ─> Conformance Pack (managed_rules_list)
```

## Deployment Flow

```
┌────────────────────────────────────────────────────────────────┐
│                    Deployment Sequence                          │
└────────────────────────────────────────────────────────────────┘

Step 1: Lambda Function Deployment
────────────────────────────────────
  ┌─────────────────────────┐
  │ 1. Upload to S3         │  (Lambda code packaged)
  │ 2. Create IAM Role      │  (Execution role + policies)
  │ 3. Create Lambda        │  (Function with code from S3)
  │ 4. Lambda Permission    │  (Allow Config to invoke)
  └─────────────────────────┘
              │
              │ depends_on
              ▼
Step 2: Organization Config Rule (Optional)
────────────────────────────────────────────
  ┌─────────────────────────┐
  │ Create Org Config Rule  │  (If not using conformance pack)
  │ • Name                  │
  │ • Lambda ARN            │
  │ • Scope                 │
  │ • Trigger types         │
  └─────────────────────────┘
              │
              │ OR (Preferred)
              ▼
Step 3: Conformance Pack Deployment
────────────────────────────────────
  ┌─────────────────────────┐
  │ 1. Generate Template    │  (Terraform templatefile)
  │    • Guard rules        │
  │    • Managed rules      │
  │    • Lambda rules       │
  │                         │
  │ 2. Deploy Pack          │  (aws_config_organization_conformance_pack)
  │    • Organization-wide  │
  │    • Excluded accounts  │
  │                         │
  │ 3. Propagate to         │  (Automatic by AWS)
  │    member accounts      │
  └─────────────────────────┘
              │
              ▼
Step 4: Validation
──────────────────
  ┌─────────────────────────┐
  │ • Check pack status     │
  │ • Verify rules active   │
  │ • Test evaluations      │
  │ • Monitor logs          │
  └─────────────────────────┘
```

## Compliance Evaluation Flow

```
┌────────────────────────────────────────────────────────────────┐
│              Resource Compliance Evaluation                     │
└────────────────────────────────────────────────────────────────┘

EFS FileSystem Created/Modified
        │
        ▼
┌───────────────────┐
│  Config Records   │  (Configuration item captured)
│  Configuration    │
└───────────────────┘
        │
        ├─────────────────────────────────────┐
        │                                     │
        ▼                                     ▼
┌───────────────────┐              ┌───────────────────┐
│  Guard Policy     │              │  AWS Managed      │
│  Evaluation       │              │  Rule Evaluation  │
│                   │              │                   │
│  • efs-is-       │              │  • efs-encrypted- │
│    encrypted     │              │    check          │
│  • Inline eval   │              │  • Native AWS     │
└───────────────────┘              └───────────────────┘
        │                                     │
        │                                     │
        └──────────────┬──────────────────────┘
                       │
                       ▼
             ┌───────────────────┐
             │  Lambda Custom    │
             │  Rule Evaluation  │
             │                   │
             │  • efs-tls-       │
             │    enforcement    │
             │  • API calls      │
             │  • Custom logic   │
             └───────────────────┘
                       │
                       ▼
             ┌───────────────────┐
             │  Compliance       │
             │  Aggregation      │
             │                   │
             │  All rule results │
             │  combined         │
             └───────────────────┘
                       │
                       ▼
             ┌───────────────────┐
             │  Final Status     │
             │                   │
             │  • COMPLIANT if   │
             │    ALL rules pass │
             │  • NON_COMPLIANT  │
             │    if ANY fail    │
             └───────────────────┘
```

## Multi-Region Deployment

```
┌────────────────────────────────────────────────────────────────┐
│                  Multi-Region Architecture                      │
└────────────────────────────────────────────────────────────────┘

                    ┌──────────────────┐
                    │  Terraform Root  │
                    │  environments/   │
                    │       prd/       │
                    └──────────────────┘
                            │
                ┌───────────┴───────────┐
                │                       │
                ▼                       ▼
        ┌──────────────┐       ┌──────────────┐
        │  us-east-2   │       │  us-east-1   │
        │  (Primary)   │       │  (Secondary) │
        └──────────────┘       └──────────────┘
                │                       │
                │                       │
    ┌───────────┼───────────┐          │
    │           │           │          │
    ▼           ▼           ▼          ▼
┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
│Lambda  │ │Config  │ │Lambda  │ │Config  │
│Function│ │Pack    │ │Function│ │Pack    │
└────────┘ └────────┘ └────────┘ └────────┘

Features:
  • Independent Lambda deployments per region
  • Separate conformance packs per region
  • Same rule logic, different Lambda ARNs
  • Regional failover capability
  • Cost: 2x Lambda functions, 2x Config rules
```

## Data Flow: EFS Policy Validation

```
┌────────────────────────────────────────────────────────────────┐
│           EFS Policy Validation Data Flow                       │
└────────────────────────────────────────────────────────────────┘

Input (Config Event):
{
  "configRuleInvokingEvent": {
    "configurationItem": {
      "resourceId": "fs-12345678",
      "resourceType": "AWS::EFS::FileSystem",
      "configuration": {...}
    }
  },
  "resultToken": "abc123..."
}
        │
        ▼
Lambda Processing:
  1. Parse event
  2. Extract resourceId
  3. Call DescribeFileSystemPolicy
        │
        ▼
EFS API Response:
{
  "Policy": "{
    \"Statement\": [{
      \"Effect\": \"Deny\",
      \"Condition\": {
        \"Bool\": {
          \"aws:SecureTransport\": \"false\"
        }
      }
    }]
  }"
}
        │
        ▼
Policy Evaluation:
  • Parse JSON
  • Find Deny statements
  • Check aws:SecureTransport
  • Determine compliance
        │
        ▼
Evaluation Result:
{
  "ComplianceType": "COMPLIANT",
  "Annotation": "Policy enforces TLS",
  "OrderingTimestamp": "2026-01-26T12:00:00.000Z"
}
        │
        ▼
Config Service:
  • Store evaluation
  • Update compliance state
  • Trigger notifications
```

## Cost Breakdown

```
┌────────────────────────────────────────────────────────────────┐
│                      Monthly Cost Estimate                      │
│                   (100 accounts, 2 regions)                     │
└────────────────────────────────────────────────────────────────┘

Config Rules:
  6 rules × 2 regions × 100 accounts = 1,200 rules
  @ $2.00 per rule per month
  = $2,400/month

Lambda Invocations:
  ~10,000 invocations/month
  Within free tier (1M free)
  = $0/month

Lambda Compute:
  ~500ms average × 10,000 invocations
  = 5,000 seconds = 83.3 GB-seconds
  Within free tier (400,000 GB-seconds free)
  = $0/month

S3 Storage (Lambda code):
  ~50 MB
  @ $0.023 per GB
  = $0.01/month

CloudWatch Logs:
  ~1 GB/month
  @ $0.50 per GB
  = $0.50/month

CloudWatch Metrics:
  Standard metrics (free)
  = $0/month

─────────────────────────────────────────
Total Monthly Cost: ~$2,400.51

Cost Optimization Tips:
  • Reduce rules where possible
  • Use scheduled notifications for non-critical rules
  • Set log retention policies
  • Review excluded accounts regularly
```

## Security Model

```
┌────────────────────────────────────────────────────────────────┐
│                     Security Architecture                       │
└────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                     Trust Boundaries                          │
└──────────────────────────────────────────────────────────────┘

    AWS Config Service ─── trusts ───> Lambda Execution Role
            │                                    │
            │                                    │
            └─── invokes ───> Lambda Function ───┘
                                      │
                                      │
                              allows only:
                              • EFS Read
                              • Config Write
                              • Logs Write

┌──────────────────────────────────────────────────────────────┐
│                   Principle of Least Privilege                │
└──────────────────────────────────────────────────────────────┘

Lambda Role Permissions:
  ✓ elasticfilesystem:Describe* (Read only)
  ✓ config:PutEvaluations (Write only eval results)
  ✓ logs:* (CloudWatch Logs only)
  ✗ elasticfilesystem:Put* (No write to EFS)
  ✗ elasticfilesystem:Delete* (No delete)
  ✗ iam:* (No IAM changes)
  ✗ config:Put* (Except PutEvaluations)

Config Service Role:
  ✓ Assume Lambda execution role
  ✓ Read resource configurations
  ✓ Write compliance data
  ✗ Modify resources
  ✗ Delete rules

┌──────────────────────────────────────────────────────────────┐
│                     Data Protection                           │
└──────────────────────────────────────────────────────────────┘

In Transit:
  • All AWS API calls use TLS 1.2+
  • Lambda to EFS: HTTPS
  • Lambda to Config: HTTPS
  • Lambda to CloudWatch: HTTPS

At Rest:
  • S3 Lambda code: Server-side encryption
  • CloudWatch Logs: Encrypted
  • Config data: Encrypted by default
  • No sensitive data in Lambda code
```

This architecture provides a comprehensive, secure, and scalable solution for EFS compliance validation across your entire AWS Organization!
