# Central bucket owner prerequisites

The `patch-outcome-observability` module is deployed to ~450 member accounts.
Every one of those accounts writes to the same central bucket via a single
IAM role name (`patch-outcome-s3-writer` by default). Nothing in the module
creates or modifies the bucket, its policy, the KMS key, or the KMS key
policy -- the bucket owner must merge the two statements below once.

Replace `<bucket>`, `<prefix>` and `o-xxxxxxxxxx` with real values (the
module's `central_prerequisites` output renders these fully resolved for
your deployment).

Two conditions are used deliberately on both statements: `aws:PrincipalOrgID`
bounds the grant to the organization, and `ArnLike` on `aws:PrincipalArn`
bounds it to the one exact role name used fleet-wide. Either alone is too
loose -- PrincipalOrgID alone would let any role in the org write, and
PrincipalArn alone (without an org boundary) wouldn't scope by account
membership at all.

## 1. Bucket policy statement to merge

```json
{
  "Sid": "AllowPatchOutcomeWritersFromOrg",
  "Effect": "Allow",
  "Principal": "*",
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::<bucket>/patchingsolution-events/outcomes/*",
  "Condition": {
    "StringEquals": { "aws:PrincipalOrgID": "o-xxxxxxxxxx" },
    "ArnLike": { "aws:PrincipalArn": "arn:aws:iam::*:role/patch-outcome-s3-writer" }
  }
}
```

## 2. KMS key policy statement to merge

```json
{
  "Sid": "AllowPatchOutcomeWritersFromOrg",
  "Effect": "Allow",
  "Principal": "*",
  "Action": ["kms:GenerateDataKey", "kms:Encrypt", "kms:DescribeKey"],
  "Resource": "*",
  "Condition": {
    "StringEquals": { "aws:PrincipalOrgID": "o-xxxxxxxxxx" },
    "ArnLike": { "aws:PrincipalArn": "arn:aws:iam::*:role/patch-outcome-s3-writer" }
  }
}
```

## Notes for the bucket owner

- The prefix `patchingsolution-events/outcomes` is a deliberate **sibling**
  of the existing `patchingsolution/` prefix, not a child of it. If the
  `s3tofirehose` labeling script matches on the `patchingsolution/` prefix,
  putting these JSON objects inside it would tag them with the
  `AWS-RunPatchBaseline` stdout sourcetype and they'd parse as garbage into
  the wrong index.
- Do not attach an explicit `Deny` elsewhere in the bucket policy that would
  catch `arn:aws:iam::*:role/patch-outcome-s3-writer` -- see open question 2
  in `BUILD-INSTRUCTIONS-infrastructure.md`.
- Confirm the bucket's Object Ownership setting (`BucketOwnerEnforced` vs.
  ACLs enabled) and tell the module consumers which `archive_object_acl`
  value to set -- see open question 1. With ACLs enabled and no
  `bucket-owner-full-control`, every `PutObject` still returns 200 while the
  bucket owner loses the ability to read its own objects, with nothing
  erroring anywhere.
