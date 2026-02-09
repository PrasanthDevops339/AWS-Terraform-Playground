# Config Conformance Pack - Local Validation Workflow

This guide helps you validate AWS Config conformance pack YAML templates **before deployment** to catch errors early.

## Problem Statement

Previously, YAML template errors in Config conformance packs were only discovered during AWS deployment, causing:
- Failed deployments with cryptic YAML parsing errors
- Wasted time troubleshooting in AWS console
- No visibility into the generated YAML before deployment

## Solution

This workflow adds **local validation** with three improvements:

1. **Local YAML file generation** - See the exact YAML before AWS sees it
2. **Terraform plan output** - Review YAML during `terraform plan`
3. **Automated validation script** - Catch common errors on Windows before pushing

---

## Quick Start (Windows)

### Prerequisites

- Terraform installed and in PATH
- PowerShell 5.1 or higher
- AWS credentials configured

### Validation Steps

```powershell
# Navigate to terraform directory
cd terraform-aft-account-customizations/exceptions/terraform

# Run validation script
.\validate-conformance-pack.ps1
```

The script will:
1. ✓ Check Terraform installation
2. ✓ Initialize Terraform
3. ✓ Run `terraform plan`
4. ✓ Validate generated YAML file
5. ✓ Check for common YAML errors

---

## Manual Validation (Alternative)

If you prefer manual validation:

### Step 1: Run Terraform Plan

```bash
terraform init
terraform plan
```

Look for the output section showing the YAML:

```
Changes to Outputs:
  + lambda_conformance_pack_yaml = <<-EOT
        Resources:
          efstlsenforcement:
            Properties:
              ...
    EOT
```

### Step 2: Check Generated YAML File

```bash
# The YAML is saved locally
cat generated-lambda-rules-conformance-pack.yaml
```

### Step 3: Validate YAML Syntax

Check for:
- [ ] No tab characters (use spaces only)
- [ ] Consistent 2-space indentation
- [ ] Starts with `Resources:`
- [ ] Lambda ARN is properly interpolated (not `${...}`)
- [ ] No special characters breaking YAML syntax

### Step 4: Compare with Working Template

Compare with the working tagging-enforcement.tf structure:

```yaml
Resources:
  resource_name:
    Properties:
      ConfigRuleName: name_${account_id}
      Source:
        Owner: CUSTOM_LAMBDA
        SourceIdentifier: "arn:aws:lambda:..."
      Type: AWS::Config::ConfigRule
```

---

## Common YAML Errors

### Error: "YAML syntax error at line 2"

**Cause:** Invalid indentation or special characters

**Fix:**
- Ensure 2-space indentation (no tabs)
- Check for unescaped special characters
- Verify template interpolations resolved correctly

### Error: "YAML syntax error at line 10"

**Cause:** Often caused by unresolved Terraform variables

**Fix:**
```terraform
# Check that module outputs are available
depends_on = [module.efs_tls_enforcement_compliance]
```

### Error: "Invalid template body"

**Cause:** Missing required YAML structure

**Fix:** Ensure YAML starts with `Resources:` section

---

## Workflow Integration

### Pre-Commit Workflow

```bash
# 1. Make changes to lambda-rules-enforcement.tf
# 2. Run validation
.\validate-conformance-pack.ps1

# 3. Review generated YAML
cat generated-lambda-rules-conformance-pack.yaml

# 4. If valid, commit and push
git add lambda-rules-enforcement.tf
git commit -m "Update EFS TLS enforcement config rule"
git push
```

### CI/CD Integration (Future)

Add to your pipeline:

```yaml
- name: Validate Conformance Pack
  run: |
    terraform init
    terraform plan
    terraform validate
```

---

## File Reference

| File | Purpose |
|------|---------|
| `lambda-rules-enforcement.tf` | Main Terraform configuration |
| `generated-lambda-rules-conformance-pack.yaml` | Generated YAML (git-ignored) |
| `validate-conformance-pack.ps1` | Windows validation script |
| `VALIDATION-README.md` | This documentation |

---

## Troubleshooting

### "Terraform not found in PATH"

**Solution:**
```powershell
# Add Terraform to PATH
$env:Path += ";C:\path\to\terraform"

# Or install via chocolatey
choco install terraform
```

### "Generated YAML file not found"

**Solution:**
Run `terraform plan` or `terraform apply` first to generate the local file.

### "Unresolved Terraform interpolations"

**Solution:**
Ensure dependencies are set correctly:
```terraform
depends_on = [module.efs_tls_enforcement_compliance]
```

---

## Benefits

✅ **Catch errors before deployment** - No more failed AWS deployments

✅ **Visual confirmation** - See exact YAML before it reaches AWS

✅ **Windows-friendly** - PowerShell script works on local Windows machines

✅ **Fast feedback** - Validate in seconds, not minutes

✅ **Version control** - Generated YAML can be reviewed in PRs

---

## Next Steps

1. Add `.gitignore` entry for generated YAML files (optional)
2. Share validation script with team
3. Add pre-commit hook for automatic validation
4. Document team workflow in confluence/wiki

## Questions?

- Check terraform plan output for YAML visibility
- Review generated YAML file in the terraform directory
- Compare with working tagging-enforcement.tf structure
