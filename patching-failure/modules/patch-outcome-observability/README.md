# patch-outcome-observability

Terraform module deployed to every AFT-vended member account. Reads SSM Run
Command terminal-status events for `AWS-RunPatchBaseline` and writes one flat
JSON record per instance/command to the central patching S3 bucket, for every
outcome -- patched, failed, or not-attempted -- so Splunk can answer "did this
instance patch" for any instance, any time.

See `PAYLOAD-SPEC-patch-outcome-record.md` for the record shape and
`BUILD-INSTRUCTIONS-infrastructure.md` for the design rationale behind every
choice below.

## What this module does NOT do

It never creates or modifies the central S3 bucket, its bucket policy, the
KMS key, or the KMS key policy. Those are owned by the bucket owner in the
central account. This module renders the two statements that owner must
merge -- see the `central_prerequisites` output and
`central-prerequisites/README.md`.

## Resources created

- 3 EventBridge rules (invocation success, invocation failure, command
  failure) on the default bus, plus 1 optional always-on canary rule
- 1 Lambda function (`src/handler.py`, provided verbatim, do not modify) and
  its log group
- 1 IAM execution role with an exact, fleet-wide-identical name
- 2 SQS dead-letter queues (EventBridge-target and Lambda-async-failure)
- Lambda permissions and an async invoke config

Deploy with `rules_enabled = false` to leave it dormant ($0 at rest, only the
canary live) and arm later by flipping that one variable.

## Usage

```hcl
module "patch_outcome_observability" {
  source = "../../modules/patch-outcome-observability"

  archive_bucket_name = "central-patching-logs-bucket"
  archive_kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/xxxxxxxx"

  rules_enabled = true
  tags = {
    Team = "platform-engineering"
  }
}
```

## Open questions (see BUILD-INSTRUCTIONS section 9)

1. Is the central bucket `BucketOwnerEnforced`, or does it have ACLs enabled?
   Decides `archive_object_acl`.
2. Does the existing bucket policy contain an explicit `Deny` that would
   catch the writer role?
3. Do SCPs or permissions boundaries restrict `lambda:CreateFunction`,
   mandate a boundary, require a role path, or force Lambda into a VPC?
4. Is `command_id` an extracted field on the stdout sourcetype, or does it
   need a `rex` on the object path?
5. Does Splunk have an instance-ID -> owner lookup? If yes, set
   `include_instance_tags = false`.
