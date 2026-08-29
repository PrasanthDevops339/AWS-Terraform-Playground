# Central bucket + KMS key — the changes the central account must make

The `patch-outcome-observability` module is deployed to ~450 member accounts.
Every one of those accounts writes to the **same** central S3 bucket, from a
Lambda running under a **single, fleet-wide-identical IAM role name**
(`patch-outcome-s3-writer` by default).

Nothing in this repo creates or modifies the bucket, its policy, the KMS key,
or the key policy. The central account owner makes exactly **two changes**:

| # | Where | Change | Required? |
|---|---|---|---|
| 1 | Central bucket policy | Add one `Allow s3:PutObject` statement scoped to the org + that one role name | **Always** |
| 2 | Central KMS key policy | Add one `Allow kms:GenerateDataKey/Encrypt` statement, same two conditions | Only if the bucket is encrypted with a **customer-managed** KMS key (SSE-KMS) |

Everything else — bucket ownership setting, existing Deny statements, the
`s3tofirehose` notification — is a *check*, not a change. Do the preflight in
§0 first: three of those checks decide whether the two statements below are
enough, and two of them can break the pipeline **silently** (200 responses,
objects in the bucket, nothing in Splunk).

Replace `<bucket>`, `<prefix>`, `<region>`, `<key-id>` and `o-xxxxxxxxxx`
throughout. The module's `central_prerequisites` output renders statements 1
and 2 fully resolved for your deployment:

```bash
terraform output -json central_prerequisites | jq
```

---

## Sample policies in this directory

Complete, copy-and-edit documents — not fragments. The bucket-policy and
key-policy samples show the **whole** policy with plausible pre-existing
statements around the new one, so it is obvious what "merge" means: add one
statement to the existing array, change nothing else.

| File | What it is | Use when |
|---|---|---|
| `sample-bucket-policy.json` | Full central bucket policy, `AllowPatchOutcomeWritersFromOrg` merged in last | Always |
| `sample-bucket-policy-acls-enabled.json` | Just the replacement statement, with `s3:PutObjectAcl` + the `s3:x-amz-acl` condition | Only if the bucket has ACLs enabled (§3 Option B) |
| `sample-kms-key-policy.json` | Full CMK key policy: root, key admins, the existing reader, plus the new writer statement | Bucket is SSE-KMS with a customer-managed key |
| `sample-kms-key-policy-hardened.json` | Just the writer statement, pinned with `kms:ViaService` | Optional hardening (§2a) |
| `sample-writer-role-policy.json` | The **member-account** side, for reference — what Terraform already puts on the writer role | Reviewing both halves of the cross-account grant |

Placeholders used throughout — replace all of them:

| Placeholder | Meaning |
|---|---|
| `central-patching-logs-bucket` | the central bucket name |
| `111111111111` | the **central** account id (bucket + key owner) |
| `222222222222` | a **member** account id (writer side, sample role policy only) |
| `o-abcd1234ef` | the AWS Organizations org id |
| `1234abcd-12ab-34cd-56ef-1234567890ab` | the central CMK key id |
| `us-east-1` | the bucket's region |
| `patch-outcome-s3-writer` | `var.writer_role_name` — must be identical in all ~450 accounts |
| `patchingsolution-events/outcomes` | `var.archive_s3_prefix` |
| `s3tofirehose-ingest`, `KeyAdministrator` | stand-ins for your real reader / admin roles — **keep your own, do not copy these** |

**The `Deny`, admin and reader statements in the samples are illustrative.**
Never paste a sample over a live policy: pull the real one down (§0.3), add
the one statement, push it back.

Merging just the new statement into a live bucket policy:

```bash
B=central-patching-logs-bucket

aws s3api get-bucket-policy --bucket $B --query Policy --output text > policy.before.json

jq --slurpfile new <(jq '.Statement[] | select(.Sid=="AllowPatchOutcomeWritersFromOrg")'       central-prerequisites/sample-bucket-policy.json | jq -s '.')    '.Statement += $new[0]' policy.before.json > policy.after.json

diff <(jq -S . policy.before.json) <(jq -S . policy.after.json)   # review
aws s3api put-bucket-policy --bucket $B --policy file://policy.after.json
```

Same shape for the key policy (`get-key-policy` / `put-key-policy`,
`--policy-name default`). Keep `policy.before.json` — it is the rollback (§7).

**A KMS key policy must always keep its root/admin statement.** Putting a key
policy without one leaves the key manageable only through whatever the
remaining statements allow, and recovering from that needs AWS Support.

---

## 0. Preflight — five things to check on the bucket before changing anything

Run these in the **central** account. Each answer feeds a decision below.

```bash
B=<bucket>

# 0.1 Object Ownership — decides whether writers must send an ACL
aws s3api get-bucket-ownership-controls --bucket $B

# 0.2 Default encryption — decides whether change #2 (KMS) is needed at all
aws s3api get-bucket-encryption --bucket $B

# 0.3 The existing bucket policy — read every Deny before you add an Allow
aws s3api get-bucket-policy --bucket $B --query Policy --output text | jq

# 0.4 Block Public Access — confirms the new statement will be accepted
aws s3api get-public-access-block --bucket $B

# 0.5 Bucket region — the writers must be told the right key, in the right region
aws s3api get-bucket-location --bucket $B
```

| Check | Answer | What it means |
|---|---|---|
| 0.1 Ownership | `BucketOwnerEnforced` | ACLs are off. Leave `archive_object_acl = null`. **Sending an ACL here fails the put with `AccessControlListNotSupported`.** |
| | `ObjectWriter` / `BucketOwnerPreferred` | ACLs are on. Writers **must** send `bucket-owner-full-control` — see §3. Preferred fix: switch the bucket to `BucketOwnerEnforced` and skip §3 entirely. |
| 0.2 Encryption | `aws:kms` with a `KMSMasterKeyID` | Change #2 is required. Give module consumers that key ARN as `archive_kms_key_arn`. |
| | `AES256` (SSE-S3), or none | Change #2 is **not** needed. Leave `archive_kms_key_arn = null` — see the warning in §2. |
| 0.3 Policy Denies | any `Deny` that could match the writer | Read §4. A Deny always wins over the Allow you are about to add. |
| 0.4 BPA | `BlockPublicPolicy: true` | Fine. A `Principal: "*"` statement constrained by `aws:PrincipalOrgID` is **not** treated as public by S3's policy evaluation, so the `put-bucket-policy` call is accepted. If your account still rejects it, use the explicit-account variant in §1b. |
| 0.5 Region | e.g. `us-east-1` | The KMS key must be in the **same region as the bucket**, and member accounts must be given that key's ARN. |

---

## 1. Change #1 — bucket policy statement (always required)

Merge this **into** the existing policy's `Statement` array. Do not replace the
policy: it already carries the AFT org statement and the `s3tofirehose`
plumbing.

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

**Why both conditions.** `aws:PrincipalOrgID` bounds the grant to the
organization; `ArnLike` on `aws:PrincipalArn` bounds it to the one exact role
name used fleet-wide. Either alone is too loose — `PrincipalOrgID` alone lets
*any* role in the org write, and `PrincipalArn` alone doesn't scope by account
membership at all.

**Why the resource is so narrow.** `s3:PutObject` on
`<prefix>/*` only — no bucket-level actions, no `s3:GetObject`, no
`s3:DeleteObject`, no `s3:ListBucket`. The writers cannot read, list, or
overwrite anything outside their own prefix, and the object keys they write
include the event id, so they cannot overwrite each other either.

**Applying it:**

```bash
aws s3api get-bucket-policy --bucket <bucket> --query Policy --output text > policy.json
# add the statement to .Statement[] with jq or an editor, then:
aws s3api put-bucket-policy --bucket <bucket> --policy file://policy.json
```

Keep the pre-change `policy.json` — it is the rollback (§7).

### 1b. Variant if `Principal: "*"` is not allowed by your guardrails

Functionally equivalent for a fixed, known account list, but it must be
updated every time AFT vends an account — which is why the org-scoped form
above is preferred:

```json
{
  "Sid": "AllowPatchOutcomeWritersFromOrg",
  "Effect": "Allow",
  "Principal": { "AWS": [
    "arn:aws:iam::111111111111:role/patch-outcome-s3-writer",
    "arn:aws:iam::222222222222:role/patch-outcome-s3-writer"
  ]},
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::<bucket>/patchingsolution-events/outcomes/*"
}
```

---

## 2. Change #2 — KMS key policy statement (only for an SSE-KMS bucket)

Needed when preflight 0.2 shows the bucket's default encryption is `aws:kms`
with a customer-managed key. Cross-account KMS use requires **both** sides:
the key policy (below) *and* the caller's IAM policy (the module already
grants it on the writer role).

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

Notes for whoever merges it:

- `Resource: "*"` inside a **key policy** means "this key" — it is not a
  wildcard across keys.
- **`kms:GenerateDataKey` is the one that actually matters.** S3 calls it on
  the writer's behalf for every SSE-KMS `PutObject`. `Encrypt` and
  `DescribeKey` are included for symmetry with the writer's IAM policy and are
  harmless.
- **No `kms:Decrypt`, deliberately.** This is a write-only path. The writers
  cannot read back a single object they wrote — including anyone who assumes
  the role.
- The existing key-policy statement for the **key administrator** and for the
  **`s3tofirehose` / Splunk reader** is untouched. That reader keeps its
  `kms:Decrypt`; without it, ingestion of these new objects breaks.

### 2a. Optional hardening — restrict to S3

Since the only KMS use is S3-side encryption, the grant can be pinned to the
S3 service:

```json
"Condition": {
  "StringEquals": {
    "aws:PrincipalOrgID": "o-xxxxxxxxxx",
    "kms:ViaService": "s3.<region>.amazonaws.com"
  },
  "ArnLike": { "aws:PrincipalArn": "arn:aws:iam::*:role/patch-outcome-s3-writer" }
}
```

Safe with this design: the Lambda never calls KMS directly (it passes
`ServerSideEncryption=aws:kms` + `SSEKMSKeyId` on `put_object` and lets S3 make
the KMS call). If you add `kms:ViaService`, drop `kms:DescribeKey` from the
action list — a direct `DescribeKey` would be denied by that condition anyway.

### 2b. If the key policy uses an `kms:EncryptionContext` condition

S3 sets the encryption context to the **object** ARN normally, but to the
**bucket** ARN when S3 Bucket Keys are enabled. A key policy pinned to
`kms:EncryptionContext:aws:s3:arn` will start denying writes the day Bucket
Keys get turned on, and vice versa. Check for that condition before merging.

### ⚠ Do not point writers at a key the bucket does not use

`archive_kms_key_arn` makes every writer send
`ServerSideEncryption=aws:kms` + that key id explicitly. If the bucket is
actually SSE-S3, or uses a *different* CMK, the objects still land — encrypted
under a key the downstream `s3tofirehose` reader has no `kms:Decrypt` on.
Writers see success, the bucket fills up, and **Splunk gets nothing**. Give
consumers the bucket's own key ARN, or `null`. Nothing in between.

---

## 3. Only if ACLs are enabled on the bucket (preflight 0.1)

**The highest-risk unknown in this design.** With Object Ownership set to
`ObjectWriter` and no ACL on the put, every `PutObject` returns **200**, the
objects accumulate, and the *bucket owner gets AccessDenied reading its own
objects*. Nothing errors anywhere, in any account.

Two options, in order of preference:

**Option A (recommended) — turn ACLs off:**

```bash
aws s3api put-bucket-ownership-controls --bucket <bucket> \
  --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'
```

Then leave `archive_object_acl = null` fleet-wide and skip the rest of §3.
Confirm nothing else in the pipeline depends on object ACLs first.

**Option B — keep ACLs, require the ACL on every write.** Three coordinated
edits, all of them required:

1. Member accounts set `archive_object_acl = "bucket-owner-full-control"`.
2. The **bucket policy** statement in §1 must also allow `s3:PutObjectAcl`,
   and should enforce the ACL value:

   ```json
   "Action": ["s3:PutObject", "s3:PutObjectAcl"],
   "Condition": {
     "StringEquals": {
       "aws:PrincipalOrgID": "o-xxxxxxxxxx",
       "s3:x-amz-acl": "bucket-owner-full-control"
     },
     "ArnLike": { "aws:PrincipalArn": "arn:aws:iam::*:role/patch-outcome-s3-writer" }
   }
   ```

3. The **writer role's own inline policy** must include `s3:PutObjectAcl`
   alongside `s3:PutObject` — a `PutObject` that carries an `x-amz-acl` header
   needs both. The module's `S3WriteOnly` statement currently grants only
   `s3:PutObject`, so **this is a module change, not just a central change**,
   if Option B is chosen.

Enforcing the ACL value in the bucket policy (step 2) is what converts the
silent-200 failure mode into a loud `AccessDenied` in the Lambda DLQ.

---

## 4. Deny statements that will break this (check 0.3)

An explicit `Deny` anywhere in the bucket policy, the KMS key policy, an SCP,
or the writer's permissions boundary beats the Allow you just added. The ones
that actually show up on a hardened central bucket:

| Deny pattern | Effect on the writers | Fix |
|---|---|---|
| Deny unless `s3:x-amz-server-side-encryption = aws:kms` | Every put fails **unless** `archive_kms_key_arn` is set | Set `archive_kms_key_arn` fleet-wide |
| Deny unless `s3:x-amz-server-side-encryption-aws-kms-key-id = <arn>` | Puts fail if consumers were given the wrong key ARN | Distribute the exact key ARN, including region and account |
| Deny unless `s3:x-amz-acl = bucket-owner-full-control` | Every put fails until §3 Option B is complete | §3 |
| Deny when `aws:SecureTransport = false` | No effect — boto3 is TLS-only | none |
| Deny unless `aws:SourceVpce` / `aws:SourceVpc` matches | **Breaks everything.** The writer Lambda is not in a VPC, so it has no VPC endpoint id | Exempt the writer role from that Deny, or accept putting 450 Lambdas in VPCs with S3 gateway + KMS interface endpoints |
| Deny unless `aws:PrincipalAccount` in a fixed list | Blocks newly vended AFT accounts as they appear | Move to `aws:PrincipalOrgID`, or accept ongoing maintenance |
| Deny on a broad `NotPrincipal` / role-name pattern | May catch `patch-outcome-s3-writer` by accident | Add an exemption for that exact role name |

---

## 5. What must **not** change on the central bucket

- **Do not create a second `aws_s3_bucket_notification`.** It is authoritative
  per bucket — a second one silently wipes the existing config and breaks
  ingestion for every account. The new prefix is picked up by the existing
  notification, or by a *modification* to it, never by a second one.
- **Do not move the prefix under `patchingsolution/`.**
  `patchingsolution-events/outcomes` is a deliberate **sibling**. If the
  `s3tofirehose` labeling script matches on the `patchingsolution/` prefix,
  these JSON objects get tagged with the `AWS-RunPatchBaseline` **stdout**
  sourcetype and parse as garbage into the wrong index — which looks like
  success from the AWS side and is worse than never arriving.
- **Do not add a lifecycle rule that expires the new prefix** on a shorter
  clock than the Splunk retention these records are meant to back.
- **Do not remove `kms:Decrypt` from the `s3tofirehose` reader** while adding
  the writer statement.

---

## 6. Verifying the change end to end

The module ships a canary rule (`source = custom.patch-canary`) precisely to
test this path without waiting for a patch cycle. `PutEvents` rejects any
source beginning with `aws.`, so a canary can never impersonate a real SSM
event — it only proves the plumbing: rule → Lambda → role → **bucket policy →
KMS grant**.

From a member account, after `terraform apply`:

```bash
# 1. get the ready-made command
terraform output -raw canary_command   # then run it

# 2. the object should be in the central bucket within seconds
aws s3 ls s3://<bucket>/patchingsolution-events/outcomes/ --recursive | tail

# 3. nothing should have landed in either DLQ
aws sqs get-queue-attributes \
  --queue-url "$(terraform output -raw lambda_dlq_url)" \
  --attribute-names ApproximateNumberOfMessages
```

If the object is missing, the Lambda log group has the exception verbatim (the
`put_object` call is deliberately not wrapped in `try/except`):

| Error in the Lambda log | Cause |
|---|---|
| `AccessDenied` on `PutObject` | statement §1 missing, wrong prefix, wrong role name, or a Deny from §4 |
| `KMS.AccessDeniedException` / `AccessDenied` mentioning the key | statement §2 missing or `kms:ViaService` too tight |
| `AccessControlListNotSupported` | `archive_object_acl` set on a `BucketOwnerEnforced` bucket (§3) |
| `InvalidArgument` on the SSE header | wrong key ARN, or key in the wrong region |
| **200, object present, bucket owner cannot read it** | §3 Option B incomplete — the silent failure |

Then, from the central account, confirm the object is readable by the *owner*
and by the `s3tofirehose` role — a `HeadObject` from the owner is the check
that catches the ACL failure mode:

```bash
aws s3api head-object --bucket <bucket> --key <the object key from step 2>
```

---

## 7. Rollback

Removing the `AllowPatchOutcomeWritersFromOrg` statement from the bucket
policy (and the key policy) stops all 450 writers immediately. Nothing else
in the central account is affected, and no already-written object is changed.
Member accounts fail closed: the exceptions surface in the Lambda DLQ and the
per-account log group, and no patching or ingestion path other than these
outcome records is touched.

To stop the writes from the member side instead, redeploy with
`rules_enabled = false` — no central change needed.

---

## 8. Summary for the bucket owner

- Two statements to merge, both scoped by `aws:PrincipalOrgID` **and** the
  exact role name `patch-outcome-s3-writer`.
- Write-only, single-prefix, no read, no list, no delete, no `kms:Decrypt`.
- Answer three questions back to the module consumers: the bucket's
  **Object Ownership** setting, the bucket's **KMS key ARN** (or "SSE-S3, no
  key"), and whether any **Deny** in §4 applies.
- Everything else in the central account stays exactly as it is.
