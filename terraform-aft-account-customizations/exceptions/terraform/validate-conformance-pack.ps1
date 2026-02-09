###############################################################################
# Windows PowerShell Script for Pre-Deployment YAML Validation               #
# Purpose: Validate Config conformance pack YAML before pushing to deployment#
###############################################################################

# Colors for output
$Success = "Green"
$Warning = "Yellow"
$Error = "Red"
$Info = "Cyan"

Write-Host "`n============================================" -ForegroundColor $Info
Write-Host "Config Conformance Pack Validation Script" -ForegroundColor $Info
Write-Host "============================================`n" -ForegroundColor $Info

# Step 1: Check if terraform is available
Write-Host "[1/5] Checking Terraform installation..." -ForegroundColor $Info
if (!(Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Terraform not found in PATH!" -ForegroundColor $Error
    exit 1
}
Write-Host "✓ Terraform found" -ForegroundColor $Success

# Step 2: Initialize terraform if needed
Write-Host "`n[2/5] Initializing Terraform..." -ForegroundColor $Info
$initOutput = terraform init -upgrade 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Terraform init failed!" -ForegroundColor $Error
    Write-Host $initOutput -ForegroundColor $Error
    exit 1
}
Write-Host "✓ Terraform initialized" -ForegroundColor $Success

# Step 3: Run terraform plan and capture output
Write-Host "`n[3/5] Running terraform plan..." -ForegroundColor $Info
$planOutput = terraform plan -out=tfplan 2>&1 | Tee-Object -Variable planCapture
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Terraform plan failed!" -ForegroundColor $Error
    Write-Host $planOutput -ForegroundColor $Error
    exit 1
}
Write-Host "✓ Terraform plan completed" -ForegroundColor $Success

# Step 4: Check if generated YAML file exists
Write-Host "`n[4/5] Validating generated YAML file..." -ForegroundColor $Info
$yamlFile = "generated-lambda-rules-conformance-pack.yaml"

if (!(Test-Path $yamlFile)) {
    Write-Host "WARNING: Generated YAML file not found!" -ForegroundColor $Warning
    Write-Host "Run 'terraform apply' to generate the YAML file, or check if local_file resource is configured." -ForegroundColor $Warning
} else {
    Write-Host "✓ Found: $yamlFile" -ForegroundColor $Success

    # Read and display YAML content
    Write-Host "`n--- Generated YAML Content ---" -ForegroundColor $Info
    $yamlContent = Get-Content $yamlFile -Raw
    Write-Host $yamlContent -ForegroundColor White
    Write-Host "--- End of YAML Content ---`n" -ForegroundColor $Info

    # Basic YAML validation
    $validationErrors = @()

    # Check for common YAML issues
    if ($yamlContent -match '\t') {
        $validationErrors += "ERROR: YAML contains tab characters (use spaces only)"
    }

    if ($yamlContent -notmatch '^Resources:') {
        $validationErrors += "ERROR: YAML must start with 'Resources:'"
    }

    if ($yamlContent -match '\$\{[^}]*\}') {
        $validationErrors += "WARNING: YAML contains unresolved Terraform interpolations: $($Matches[0])"
    }

    if ($yamlContent -match 'Owner:\s*CUSTOM_LAMBDA') {
        Write-Host "✓ Custom Lambda owner detected" -ForegroundColor $Success
    }

    if ($yamlContent -match 'arn:aws:lambda:') {
        Write-Host "✓ Lambda ARN found in YAML" -ForegroundColor $Success
    } else {
        $validationErrors += "WARNING: No Lambda ARN found - ensure Lambda module is deployed"
    }

    # Check indentation consistency (should be 2 spaces per level)
    $lines = $yamlContent -split "`n"
    $inconsistentIndent = $false
    foreach ($line in $lines) {
        if ($line -match '^( +)' -and $matches[1].Length % 2 -ne 0) {
            $inconsistentIndent = $true
            break
        }
    }
    if ($inconsistentIndent) {
        $validationErrors += "ERROR: Inconsistent indentation detected (use 2 spaces per level)"
    }

    # Display validation results
    if ($validationErrors.Count -eq 0) {
        Write-Host "✓ YAML validation passed!" -ForegroundColor $Success
    } else {
        Write-Host "`nValidation Issues Found:" -ForegroundColor $Warning
        foreach ($err in $validationErrors) {
            if ($err -like "ERROR:*") {
                Write-Host "  $err" -ForegroundColor $Error
            } else {
                Write-Host "  $err" -ForegroundColor $Warning
            }
        }
    }
}

# Step 5: Show terraform output with YAML
Write-Host "`n[5/5] Checking Terraform outputs..." -ForegroundColor $Info
$outputs = terraform output -json 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Terraform outputs available" -ForegroundColor $Success
    Write-Host "`nTo view the YAML output:" -ForegroundColor $Info
    Write-Host "  terraform output lambda_conformance_pack_yaml" -ForegroundColor $Info
} else {
    Write-Host "NOTE: No outputs available yet (run terraform apply first)" -ForegroundColor $Warning
}

# Summary
Write-Host "`n============================================" -ForegroundColor $Info
Write-Host "Validation Summary" -ForegroundColor $Info
Write-Host "============================================" -ForegroundColor $Info
Write-Host "Next Steps:" -ForegroundColor $Info
Write-Host "  1. Review the generated YAML above" -ForegroundColor White
Write-Host "  2. Check for any validation errors or warnings" -ForegroundColor White
Write-Host "  3. If valid, commit and push to deployment" -ForegroundColor White
Write-Host "`nTo apply changes:" -ForegroundColor $Info
Write-Host "  terraform apply tfplan" -ForegroundColor White
Write-Host "`nTo view just the YAML:" -ForegroundColor $Info
Write-Host "  cat $yamlFile" -ForegroundColor White
Write-Host "`n============================================`n" -ForegroundColor $Info
