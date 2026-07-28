#!/usr/bin/env bash
#
# test.sh — Cross-account SSM patch log delivery diagnostic
#
# Run this ON the EC2 managed node (workload account 111111111111) so it
# executes as the same identity the SSM Agent uses (instance profile role).
#
# Usage:
#   chmod +x test.sh
#   ./test.sh
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Config — edit if your bucket/prefix/key change
# ---------------------------------------------------------------------------
BUCKET="operations-dev-test-patch-reports-use2"
PREFIX="patchingsolution/AWSLogs/111111111111/PatchRunCommand"
KEY_ARN="arn:aws:kms:us-east-2:222222222222:key/mrk-85d0d56467474747474"

PROBE_FILE="$(mktemp /tmp/ssm-patch-probe.XXXXXX)"
trap 'rm -f "$PROBE_FILE"' EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
PASS="✅"
FAIL="❌"
INFO="ℹ️ "

section() { printf '\n=== %s ===\n' "$1"; }
ok()      { printf '%s %s\n' "$PASS" "$1"; }
bad()     { printf '%s %s\n' "$FAIL" "$1"; }
info()    { printf '%s %s\n' "$INFO" "$1"; }

# ---------------------------------------------------------------------------
# 1 — Can it read the bucket's encryption config? (also reveals key ID vs ARN)
# ---------------------------------------------------------------------------
section "1. GetBucketEncryption"
if ENC_JSON=$(aws s3api get-bucket-encryption --bucket "$BUCKET" --output json 2>&1); then
  echo "$ENC_JSON"
  ok "GetBucketEncryption succeeded"
  if echo "$ENC_JSON" | grep -q '"KMSMasterKeyID": *"arn:aws:kms:'; then
    ok "Bucket default encryption uses a full KMS key ARN"
  else
    bad "Bucket default encryption does NOT show a full ARN — bare key ID/alias detected"
    info "SSM Agent resolves a bare key ID against ITS OWN account and will fail to find the key."
    info "Fix: set kms_master_key_id to the full ARN in the bucket's SSE config."
  fi
else
  bad "GetBucketEncryption failed: $ENC_JSON"
  info "Check: s3:GetEncryptionConfiguration on the BUCKET arn (not /*), in both IAM and bucket policy."
fi

# ---------------------------------------------------------------------------
# 2 — The real test: PutObject relying on bucket default encryption
#     (this is exactly what the SSM Agent does)
# ---------------------------------------------------------------------------
section "2. PutObject probe (bucket default encryption, like the SSM Agent)"
echo "probe $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$PROBE_FILE"
PROBE_KEY="${PREFIX}/diag/probe-$(date +%s).txt"

if PUT_OUT=$(aws s3api put-object --bucket "$BUCKET" --key "$PROBE_KEY" --body "$PROBE_FILE" --output json 2>&1); then
  echo "$PUT_OUT"
  ok "PutObject succeeded → s3://$BUCKET/$PROBE_KEY"
  info "IAM path is healthy end-to-end. If AWS-RunPatchBaseline logs still don't land,"
  info "check the SSM Agent version, Object Ownership setting, and the exact plugin"
  info "subfolder (PatchLinux/PatchWindows), not IAM."
else
  bad "PutObject failed:"
  echo "$PUT_OUT"
  info "Compare this exact error against the diagnostic matrix:"
  info "  - AccessDenied mentioning KMS -> key policy in 222222222222 doesn't grant this caller"
  info "  - AccessDenied with no KMS mention -> bucket policy Principal/Resource/Condition mismatch"
  info "  - explicit deny -> an SCP or bucket-policy Deny is blocking this, not a missing Allow"
fi

# ---------------------------------------------------------------------------
# 3 — Explicit-key probe: isolates key RESOLUTION vs key PERMISSION
# ---------------------------------------------------------------------------
section "3. PutObject probe (explicit KMS key ARN)"
PROBE_KEY2="${PREFIX}/diag/probe-explicit-$(date +%s).txt"

if PUT_OUT2=$(aws s3api put-object --bucket "$BUCKET" --key "$PROBE_KEY2" --body "$PROBE_FILE" \
    --server-side-encryption aws:kms --ssekms-key-id "$KEY_ARN" --output json 2>&1); then
  echo "$PUT_OUT2"
  ok "PutObject with explicit key ARN succeeded → s3://$BUCKET/$PROBE_KEY2"
else
  bad "PutObject with explicit key ARN failed:"
  echo "$PUT_OUT2"
fi

# ---------------------------------------------------------------------------
# Verdict matrix
# ---------------------------------------------------------------------------
section "Interpretation"
cat <<'EOF'
Step 1 fail                      -> missing s3:GetEncryptionConfiguration (IAM and/or bucket policy)
Step 2 fail, Step 3 pass         -> bucket default encryption uses bare key ID, not ARN (see Step 1 output)
Step 2 fail, Step 3 fail         -> KMS key policy OR bucket policy deny (not a default-encryption issue)
Step 1/2/3 all pass               -> IAM chain is healthy; look at Object Ownership, agent version, or plugin subfolder
EOF
