# Runbook — KMS Key Policy Lockout Cleanup (CITP-1774)

**Repo:** ``
**Account:** `000000000000` · **Region:** `us-east-2` · **Env:** `dev`
**Key:** `mrk-####################` (multi-region, symmetric)
**Status:** One-shot remediation — remove from the pipeline once complete.

---

## 1. Problem Statement

A restrictive key policy was applied to the KMS key created by the
`test-patching-bucket-kms-key` module. The `KeyAdministration` statement grants
13 actions to `arn:aws:iam:33333333:role/-dev-`
but **omits `kms:GetKeyRotationStatus`**, and the policy has no
`Enable IAM User Permissions` statement delegating to the account root.

KMS key policies are the root of trust: if an action is absent from the key
policy, no IAM policy can grant it.

### Failure chain

| Stage | Behaviour |
|---|---|
| First `plan` | Passed — old policy still in effect |
| First `apply` | `PutKeyPolicy` **succeeded**, post-apply read failed → job marked failed |
| All later `plan`s | Refresh calls `GetKeyRotationStatus` → `AccessDeniedException` (400) |
| Removing resource from code | No help — Terraform must refresh state before planning a destroy |

### Observed error

```
Error: reading KMS Key (mrk-5555): rotation enabled:
operation error KMS: GetKeyRotationStatus, https response error StatusCode: 400,
api error AccessDeniedException: User: arn:aws:sts::3333333333333:assumed-role/
operations-dev-administrator/[MASKED] is not authorized to perform:
kms:GetKeyRotationStatus on resource: arn:aws:kms:us-east-2:33333333333:key/
mrk-5555555 because no resource-based policy allows
the kms:GetKeyRotationStatus action
```

### Key facts

- `bypass_policy_lockout_safety_check = false` did its job — `kms:PutKeyPolicy`
  was retained, so the role is **not fully locked out**.
- The Terraform state file is **not** the blocker. The resource-based policy is.
- The AWS provider read path for `aws_kms_key` calls `DescribeKey`,
  `GetKeyPolicy`, `ListResourceTags`, **`GetKeyRotationStatus`** and (provider
  ≥ 5.60) `ListKeyRotations`.

---

## 2. Remediation Options

| # | Option | Blast radius | When to use |
|---|---|---|---|
| **A** | `put-key-policy` with the missing actions | None — key preserved | **Default.** Fastest, non-destructive |
| **B** | `terraform state rm` only | Orphans a live key | Escape hatch to unblock plan without deleting |
| **C** | Delete alias + `schedule-key-deletion` | Destroys the key and all data encrypted with it | Only when a clean key is genuinely wanted |

This runbook covers **Option C** via pipeline, since that was the requested
path. Option A is documented in §6 and **must be applied to the module either
way** — otherwise the next `apply` recreates a key with the identical lockout.

---

## 3. Pre-Flight Checks

- [ ] Confirm the key is genuinely disposable — `test-patching-bucket-kms-key`
      suggests non-production, but verify no objects you care about exist in the
      associated S3 bucket.
- [ ] Confirm the bucket's default encryption config does not reference the key
      ARN in a way that breaks on deletion.
- [ ] Confirm the MRK has **no replica keys** — the primary will not delete
      while replicas exist. The job guards on this.
- [ ] **Fix the module policy first** (§6) and have that MR ready.
- [ ] Separately: do **not** apply the run showing
      `module.secret_key_db.aws_kms_key.primary` planned for destroy. That is a
      different key encrypting secrets, and the destroy is caused by a
      `count`/conditional change from a module version bump. Diff the module
      version before touching it.

---

## 4. The Pipeline Job

Add to `.gitlab-ci.yml`. The `rules:` gate keeps the job dormant on normal
pipelines — deliberate, because `.pre` runs on **every** commit and MR, and an
unguarded destructive job would fail the whole pipeline once the key is gone.

```yaml
include:
  - project: "ipeline-templates"
    ref: "main"
    file: 'ixxxxxxx.yml'

variables:
  ENABLED_ENVIRONMENTS: dev
  GROUP: o
  NONPROD_USERNAME: $
  NONPROD_PASSWORD: $n

kms-cleanup:
  stage: .pre
  tags: [""]
  rules:
    - if: '$KMS_CLEANUP == "true"'
  variables:
    ENV: dev
    AWS_REGION: us-east-2
    KMS_KEY_ID: mrk-
    DELETION_WINDOW: "7"
    DRY_RUN: "true"
  script:
    - python3 /xxxxxxxxx.py -e $ENV -g $GROUP -u $NONPROD_U-p $NONPROD
    - export AWS_PROFILE=

    # --- Guard: identity, key state, MRK replicas ---
    - aws sts get-caller-identity
    - |
      STATE=$(aws kms describe-key --key-id $KMS_KEY_ID --region $AWS_REGION \
        --query 'KeyMetadata.KeyState' --output text)
      echo "Key state: $STATE"
      if [ "$STATE" = "PendingDeletion" ]; then
        echo "Already pending deletion — nothing to do."; exit 0
      fi
    - |
      REPLICAS=$(aws kms describe-key --key-id $KMS_KEY_ID --region $AWS_REGION \
        --query 'KeyMetadata.MultiRegionConfiguration.ReplicaKeys' --output json)
      echo "Replica keys: $REPLICAS"
      if [ "$REPLICAS" != "null" ] && [ "$REPLICAS" != "[]" ]; then
        echo "ERROR: MRK has replicas. Schedule those first."; exit 1
      fi

    # --- Aliases (must be removed or next CreateAlias throws AlreadyExists) ---
    - |
      ALIASES=$(aws kms list-aliases --key-id $KMS_KEY_ID --region $AWS_REGION \
        --query 'Aliases[].AliasName' --output text)
      echo "Aliases found: ${ALIASES:-none}"
      for A in $ALIASES; do
        if [ "$DRY_RUN" = "true" ]; then
          echo "[dryrun] would delete-alias $A"
        else
          aws kms delete-alias --alias-name "$A" --region $AWS_REGION
          echo "deleted alias $A"
        fi
      done

    # --- Schedule key deletion ---
    - |
      if [ "$DRY_RUN" = "true" ]; then
        echo "[dryrun] would schedule-key-deletion $KMS_KEY_ID (${DELETION_WINDOW}d)"
      else
        aws kms schedule-key-deletion --key-id $KMS_KEY_ID \
          --days $DELETION_WINDOW --region $AWS_REGION
      fi
```

### Gating alternatives

| Approach | Trade-off |
|---|---|
| `if: '$KMS_CLEANUP == "true"'` | **Recommended.** Explicit opt-in on a destructive action |
| `if: '$CI_COMMIT_BRANCH == "kms-cleanup-1774"'` | No variable to remember; dies with the branch |
| `when: manual` | Doesn't block downstream, but leaves a clickable destroy button in every pipeline forever |

---

## 5. Execution Sequence

1. **Dry run** — *Run pipeline* → add variable `KMS_CLEANUP=true`. `DRY_RUN`
   defaults to `true`.
2. **Verify job output**: caller identity is the expected role, key state is
   `Enabled`, replica list is empty, alias names match expectations.
3. **Live run** — *Run pipeline* → `KMS_CLEANUP=true` **and** `DRY_RUN=false`.
4. **Confirm** the key reports `PendingDeletion`:
   ```bash
   aws kms describe-key --key-id mrk-6f831e27f40d416ca71cc9223c91e0ad \
     --region us-east-2 --query 'KeyMetadata.KeyState'
   ```
5. **Re-run the normal pipeline.** The plan will refresh clean — the AWS
   provider treats `PendingDeletion` as *not found* and drops the resource from
   state before it ever reaches the failing `GetKeyRotationStatus` call.
6. **Merge the module policy fix** (§6) before allowing any `apply` that
   recreates the key.
7. **Remove the `kms-cleanup` job** from `.gitlab-ci.yml` in the same MR.

### Optional — explicit state removal

Usually unnecessary (step 5 handles it). If you want it explicit, run before
the terraform job, in the same working directory the template uses:

```yaml
    - ACCOUNT_ALIAS=$(aws iam list-account-aliases --query 'AccountAliases[0]' --output text)
    - TF_BACKEND_S3_BUCKET=$ACCOUNT_ALIAS-tf-backend-use2
    - TF_STATE_FILE_NAME=$CI_PROJECT_NAME/$ENV
    - |
      terraform init -reconfigure \
        -backend-config="bucket=$TF_BACKEND_S3_BUCKET" \
        -backend-config="key=$TF_STATE_FILE_NAME" \
        -backend-config="region=$AWS_REGION"
      terraform state rm 'module.test-patching-bucket-kms-key.aws_kms_key.primary[0]'
```

Watch for lock contention if `iac-root.yml` runs its own `init`.

---

## 6. The Actual Fix — Module Key Policy

**This is mandatory regardless of which remediation option you take.**

### Preferred: add root delegation

Explicit-only key policies break on every provider upgrade that introduces a
new read call. Include the standard statement unless there is a hard reason not
to:

```json
{
  "Sid": "EnableIAMUserPermissions",
  "Effect": "Allow",
  "Principal": { "AWS": "arn:aws:iam::000000000000:root" },
  "Action": "kms:*",
  "Resource": "*"
}
```

### If the explicit-only pattern must stay

Add these to the `KeyAdministration` action list:

```
kms:GetKeyRotationStatus     # the immediate cause
kms:ListKeyRotations         # provider >= 5.60, rotation_period_in_days
kms:UpdateKeyDescription
kms:EnableKey
kms:DisableKey
kms:ReplicateKey             # required for MRK
kms:UpdatePrimaryRegion      # required for MRK
```

### Option A — non-destructive fix on the existing key

```bash
aws kms get-key-policy \
  --key-id mrk- \
  --policy-name default --region us-east-2 \
  --query Policy --output text > key-policy.json
  # edit key-policy.json — add the actions above

aws kms put-key-policy \
  --key-id mrk- \
  --policy-name default --policy file://key-policy.json --region us-east-2
```

`kms:PutKeyPolicy` is already granted to the role, so this works today. Mirror
the change in the module so the next plan is a no-op.

---

## 7. Rollback

| Point of failure | Recovery |
|---|---|
| Alias deleted, deletion not yet scheduled | Re-create the alias: `aws kms create-alias --alias-name <name> --target-key-id <key>` |
| Deletion scheduled, within the window | `aws kms cancel-key-deletion --key-id <key> --region us-east-2`, then re-create the alias |
| Deletion window elapsed | **No recovery.** Key and all ciphertext under it are unrecoverable |

The 7-day window is the entire safety net. Do not shorten it.

---

## 8. Validation Checklist

- [ ] Dry-run output reviewed and matches expectations
- [ ] Caller identity confirmed as `operations-dev-administrator` in `000000000000`
- [ ] MRK replica list empty
- [ ] Aliases enumerated and deleted
- [ ] Key reports `PendingDeletion`
- [ ] Terraform plan refreshes without the `GetKeyRotationStatus` error
- [ ] Module key policy updated with the missing actions
- [ ] New key created by the corrected module reads cleanly on plan
- [ ] `kms-cleanup` job removed from `.gitlab-ci.yml`
- [ ] `secret_key_db` destroy plan investigated separately

---

## 9. Systemic Follow-Ups

Turning this one-off into platform capability:

1. **Guardrail the pattern.** Add an OPA/Sentinel policy at plan time that
   rejects any `aws_kms_key` whose policy lacks either the root delegation
   statement or the full Terraform-required read action set. This class of
   lockout then becomes impossible org-wide, not just in this repo.
2. **Golden KMS module.** Publish a versioned TFE module with the correct
   baseline policy and validated inputs, so teams compose statements on top of
   a safe base rather than authoring policies from scratch.
3. **Provider-upgrade checklist.** Every AWS provider bump can add new read
   calls. Root delegation makes this a non-event; explicit-only policies need a
   review step.
4. **Reusable cleanup template.** Generalise the `.pre` job into the shared
   `pipeline-templates` project as a parameterised, gated maintenance job
   (`.kms-cleanup`) so the next team doesn't rebuild it under incident pressure.
5. **Teaching note.** The transferable lesson: *resource-based policies on KMS
   are the root of trust — IAM cannot rescue you.* Worth a short KT session,
   since the same trap exists for S3 bucket policies and Secrets Manager
   resource policies.
