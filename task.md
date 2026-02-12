# Implementation Plan: AMI Governance Controls

## Overview

This implementation plan converts the AMI Governance Controls design into actionable Terraform coding tasks. The implementation works within the existing `aws-service-control-policies` repository structure, updating policy JSON templates and environment configurations to enforce Prasa Operations AMI governance.

**Repository**: `aws-service-control-policies`
**Approach**: Update existing policy JSON templates and environment configurations (no new module needed)
**Key Pattern**: Template-based policy generation using `templatefile()` with date-stamped JSON files

The implementation follows a phased approach:
1. Update policy JSON templates to use template variables
2. Update environment configurations with Prasa account IDs and enforcement settings
3. Enable and configure exception expiry feature
4. Comprehensive testing and validation in dev environment
5. Production deployment with audit mode
6. Monitor and switch to enforcement mode

## Tasks

- [ ] 1. Update declarative policy JSON template with template variables
  - [x] 1.1 Review current policy structure
    - Read `aws-service-control-policies/policies/declarative-policy-ec2-2026-01-18.json`
    - Identify hardcoded account IDs that need to be parameterized
    - Verify the current `ec2` wrapper structure
    - Document any organization-specific customizations
    - _Requirements: 4.1_
  
  - [x] 1.2 Add template variables for account lists
    - Replace hardcoded Prasa Operations account IDs with: `${jsonencode(ops_accounts)}`
    - Add conditional support for vendor accounts: `${jsonencode(vendor_accounts)}`
    - Add conditional support for exception accounts: `${jsonencode(active_exception_accounts)}`
    - Ensure proper JSON array formatting in template
    - _Requirements: 1.1, 1.2, 2.2, 3.6, 10.1_
  
  - [x] 1.3 Add enforcement mode template variable
    - Replace hardcoded enforcement state with: `${enforcement_mode}`
    - Ensure valid values are "audit_mode" or "enabled"
    - Add comment documenting enforcement mode options
    - _Requirements: 5.1, 5.2, 5.3_
  
  - [x] 1.4 Update exception message with template variables
    - Add template variable for AMI name patterns list
    - Add template variable for exception request URL
    - Add template variable for maximum exception duration
    - Include account ID aliases in message
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_
  
  - [x] 1.5 Add optional AMI age and deprecation conditions
    - Add conditional `creation_date_condition` block using `%{ if }` syntax
    - Add conditional `deprecation_time_condition` block using `%{ if }` syntax
    - Add template variables: `ami_max_age_days`, `ami_max_deprecation_days`
    - Add comments explaining when to use these conditions
    - _Requirements: 1.5_

- [ ] 2. Update SCP JSON template with template variables
  - [x] 2.1 Review current SCP structure
    - Read `aws-service-control-policies/policies/scp-ami-guardrail-2026-01-18.json`
    - Identify all hardcoded account IDs in conditions
    - Verify all three statement blocks are present (launch, creation, public sharing)
    - _Requirements: 4.2_
  
  - [x] 2.2 Parameterize account IDs in launch restrictions
    - Replace hardcoded account IDs in `ec2:Owner` condition with: `${jsonencode(ops_accounts)}`
    - Add support for vendor accounts in the same condition
    - Add support for exception accounts in the same condition
    - Ensure account list matches declarative policy exactly
    - _Requirements: 4.5, 10.4_
  
  - [x] 2.3 Verify AMI creation and side-loading blocks
    - Confirm CreateImage, CopyImage, RegisterImage, ImportImage are all denied
    - Ensure no account-based conditions (applies to all accounts)
    - Add comments explaining side-loading prevention
    - _Requirements: 4.6_
  
  - [x] 2.4 Verify public AMI sharing block
    - Confirm ModifyImageAttribute is denied when ec2:Add/group = "all"
    - Add comments explaining public sharing prevention
    - _Requirements: 4.7, 6.1, 6.2_

- [ ] 3. Update production environment configuration
  - [-] 3.1 Update declarative policy module invocation
    - Edit `aws-service-control-policies/environments/prd/main.tf`
    - Locate `module "declarative-policy-ec2"` block
    - Add `policy_vars` map with:
      - `ops_accounts = ["565656565656", "666363636363"]`
      - `enforcement_mode = "audit_mode"` (initial rollout)
      - `ami_name_patterns = ["prasa-rhel8-*", "prasa-rhel9-*", ...]` (all approved patterns)
      - `exception_request_url = "<Jira URL>"`
    - Verify `target_ids` includes workloads and sandbox OUs
    - Add inline documentation comments explaining each variable
    - _Requirements: 1.1, 1.2, 1.5, 5.1, 7.2, 7.3, 8.3, 8.6_
  
  - [~] 3.2 Update SCP module invocation
    - Edit `aws-service-control-policies/environments/prd/main.tf`
    - Locate `module "scp-ami-guardrail"` block
    - Add `policy_vars` map with same `ops_accounts` as declarative policy
    - Verify `target_ids` matches declarative policy targets
    - Add inline documentation comments
    - _Requirements: 1.1, 1.2, 4.2, 7.5, 10.4_
  
  - [~] 3.3 Configure resource tagging
    - Add `tags` parameter to both module invocations
    - Include: `Environment = "prd"`, `ManagedBy = "Terraform"`, `PolicyType = "<type>"`
    - Add custom tags: `Owner = "Cloud Platform Team"`, `Purpose = "AMI Governance"`
    - _Requirements: 14.1, 14.2, 14.3, 14.4, 14.5, 14.6_

- [ ] 4. Configure exception expiry feature
  - [~] 4.1 Enable exception expiry in module invocations
    - Update both module blocks in `environments/prd/main.tf`
    - Set `enable_exception_expiry = true`
    - Add empty `exception_accounts = {}` map (no exceptions initially)
    - Add multi-line comment explaining exception format
    - _Requirements: 3.1, 3.2, 3.3_
  
  - [~] 4.2 Document exception account format
    - Add comment block showing example exception:
      ```hcl
      # exception_accounts = {
      #   "123456789012" = "2026-06-30"  # Migration project - expires June 30
      #   "987654321098" = "2026-03-15"  # Vendor testing - expires March 15
      # }
      ```
    - Document YYYY-MM-DD date format requirement
    - Document maximum exception duration (365 days for exception AMIs, 90 days for others)
    - _Requirements: 3.1, 15.4, 15.5_
  
  - [~] 4.3 Add exception expiry validation
    - Verify module's built-in expiry validation is active
    - Confirm expired exceptions will fail terraform apply
    - Document error message format in comments
    - _Requirements: 3.4, 17.1, 17.2, 17.3, 17.4, 17.5_

- [ ] 5. Create dev environment configuration
  - [~] 5.1 Copy production configuration to dev
    - Copy `environments/prd/main.tf` structure to `environments/dev/main.tf`
    - Update target_ids to reference dev OU variables (var.dev_workloads, var.dev_sandbox)
    - Keep same Prasa Operations account IDs
    - Keep enforcement_mode as "audit_mode"
    - Update tags: `Environment = "dev"`
    - _Requirements: 12.1, 12.2, 18.7_
  
  - [~] 5.2 Update dev variables file
    - Edit `environments/dev/variables.tf`
    - Ensure variables exist for dev target OUs
    - Add descriptions for each variable
    - Document which OUs are used for testing
    - _Requirements: 7.1, 7.2, 7.3_
  
  - [~] 5.3 Add dev-specific documentation
    - Add comment block at top of dev/main.tf
    - Explain this is for testing before production rollout
    - Document differences from production (target OUs)
    - Note that account IDs should match production
    - _Requirements: 12.1, 12.4_

- [ ] 6. Validate Terraform configuration
  - [~] 6.1 Validate syntax and structure
    - Run `terraform init` in environments/dev
    - Run `terraform validate` in environments/dev
    - Fix any syntax errors or validation issues
    - Verify provider versions meet requirements (AWS >= 5.0)
    - _Requirements: 9.1, 9.2, 20.1, 20.2, 20.3_
  
  - [~] 6.2 Validate policy JSON templates
    - Run `terraform plan` in environments/dev
    - Verify templatefile() successfully loads JSON files
    - Verify jsondecode() parses templates without errors
    - Check that policy_vars are correctly injected
    - _Requirements: 9.3, 9.4_
  
  - [~] 6.3 Review planned changes
    - Examine terraform plan output
    - Verify two policies will be created (declarative + SCP)
    - Verify policy attachments for each target_id
    - Verify policy content includes correct account IDs
    - Confirm no unexpected resource changes
    - _Requirements: 9.7, 9.8_

- [ ] 7. Deploy and validate in dev environment
  - [~] 7.1 Deploy policies to dev
    - Run `terraform apply` in environments/dev
    - Confirm creation of both policies
    - Confirm policy attachments to target OUs
    - Save policy IDs from terraform output
    - _Requirements: 9.7, 9.8, 16.1, 16.2_
  
  - [~] 7.2 Verify policy content in AWS console
    - Open AWS Organizations console
    - Navigate to Policies → Declarative policies
    - Verify declarative-policy-ec2 exists with correct content
    - Navigate to Policies → Service control policies
    - Verify scp-ami-guardrail exists with correct content
    - Check that account IDs match configuration (565656565656, 666363636363)
    - _Requirements: 1.1, 1.2, 10.4_
  
  - [~] 7.3 Check effective policies on dev accounts
    - Run: `aws organizations describe-effective-policy --policy-type DECLARATIVE_POLICY_EC2 --target-id <dev-account-id>`
    - Verify effective policy includes AMI governance rules
    - Verify allowed_image_providers contains Prasa Operations accounts
    - Verify enforcement state is "audit_mode"
    - Run same check for SERVICE_CONTROL_POLICY type
    - _Requirements: 11.1, 11.2, 11.3, 11.4_
  
  - [~] 7.4 Verify policy attachments
    - Run: `aws organizations list-policies-for-target --target-id <dev-ou-id> --filter DECLARATIVE_POLICY_EC2`
    - Verify declarative policy is attached
    - Run: `aws organizations list-policies-for-target --target-id <dev-ou-id> --filter SERVICE_CONTROL_POLICY`
    - Verify SCP is attached
    - Repeat for all target OUs
    - _Requirements: 7.5, 18.1_

- [ ] 8. Test enforcement scenarios in dev
  - [~] 8.1 Test approved AMI launch (should succeed)
    - Launch EC2 instance in dev account using AMI from 565656565656
    - Verify launch succeeds without errors
    - Launch EC2 instance using AMI from 666363636363
    - Verify launch succeeds without errors
    - Check CloudTrail logs for successful RunInstances events
    - _Requirements: 1.3, 13.1_
  
  - [~] 8.2 Test non-approved AMI launch in audit mode (should succeed but log)
    - Launch EC2 instance using public AWS AMI (e.g., Amazon Linux 2)
    - Verify launch succeeds (audit mode allows it)
    - Query CloudTrail: `aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances`
    - Verify logs show imageAllowed=false indicator
    - Verify SCP does not block (only declarative policy in audit mode)
    - _Requirements: 5.2, 5.4, 13.2_
  
  - [~] 8.3 Test AMI creation attempt (should be denied by SCP)
    - Attempt to create custom AMI: `aws ec2 create-image --instance-id <id> --name test-ami`
    - Verify action is denied with AccessDenied error
    - Verify error message references SCP
    - Check CloudTrail for denied CreateImage event
    - _Requirements: 4.6, 13.3_
  
  - [~] 8.4 Test public AMI sharing attempt (should be denied)
    - Create or use existing AMI in dev account
    - Attempt to make it public: `aws ec2 modify-image-attribute --image-id <ami-id> --launch-permission "Add=[{Group=all}]"`
    - Verify action is denied
    - Verify error message indicates policy violation
    - _Requirements: 4.7, 6.1, 6.2, 13.4_
  
  - [~] 8.5 Verify custom error message
    - Attempt non-approved AMI launch in dev account
    - Capture error message from AWS console or CLI
    - Verify message includes approved AMI name patterns
    - Verify message includes Prasa Operations account IDs
    - Verify message includes exception request URL
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_

- [ ] 9. Test exception expiry functionality
  - [~] 9.1 Add test exception with future expiry
    - Edit `environments/dev/main.tf`
    - Add test exception account to both module invocations:
      ```hcl
      exception_accounts = {
        "999999999999" = "2026-12-31"  # Test exception
      }
      ```
    - Run `terraform plan`
    - Verify plan shows policy updates with new account in allowlist
    - _Requirements: 3.1, 3.2_
  
  - [~] 9.2 Apply and verify active exception
    - Run `terraform apply`
    - Verify policies updated with exception account
    - Check policy content includes 999999999999 in allowed_image_providers
    - Verify no errors about expired exceptions
    - _Requirements: 3.2, 3.6_
  
  - [~] 9.3 Test expired exception detection
    - Edit `environments/dev/main.tf`
    - Change exception date to past: `"999999999999" = "2025-01-01"`
    - Run `terraform plan`
    - Verify plan fails with error about expired exception
    - Verify error message lists account ID and expiry date
    - _Requirements: 3.3, 3.4, 17.1, 17.2, 17.3, 17.4, 17.5_
  
  - [~] 9.4 Remove test exception
    - Edit `environments/dev/main.tf`
    - Remove test exception from exception_accounts map
    - Run `terraform apply`
    - Verify policies updated to remove exception account
    - _Requirements: 16.4, 30.1_

- [~] 10. Checkpoint - Dev environment validation complete
  - Verify all dev tests passed
  - Verify policies deployed correctly
  - Verify enforcement scenarios work as expected
  - Verify exception expiry logic works correctly
  - Document any issues or unexpected behaviors
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 11. Create operational documentation
  - [~] 11.1 Create exception request process document
    - Create `aws-service-control-policies/docs/AMI-EXCEPTION-PROCESS.md`
    - Document who can request exceptions (developers, project teams)
    - Document what information is required (business justification, security approval)
    - Document maximum exception durations (365 days for exception AMIs, 90 days for others)
    - Document approval workflow (Cloud Platform Team approval)
    - Include Jira ticket URL for submissions
    - Provide example exception request
    - _Requirements: 15.1, 15.2, 15.3, 15.4, 15.5, 15.6, 15.7_
  
  - [~] 11.2 Create deployment guide
    - Create `aws-service-control-policies/docs/AMI-GOVERNANCE-DEPLOYMENT.md`
    - Document pre-deployment checklist
    - Document deployment steps for each environment
    - Document validation steps after deployment
    - Document rollback procedures
    - Include troubleshooting section
    - _Requirements: 12.1, 12.2_
  
  - [~] 11.3 Create monitoring and operations guide
    - Create `aws-service-control-policies/docs/AMI-GOVERNANCE-MONITORING.md`
    - Document CloudTrail log queries for policy evaluations
    - Document how to check imageAllowed indicators in audit mode
    - Document how to monitor exception expiry
    - Provide example AWS CLI commands
    - Document alerting recommendations
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5_
  
  - [~] 11.4 Create operational runbook
    - Create `aws-service-control-policies/docs/AMI-GOVERNANCE-RUNBOOK.md`
    - Document how to add new exception account
    - Document how to remove expired exception
    - Document how to add vendor AMI publisher account
    - Document how to troubleshoot blocked launches
    - Document how to switch from audit mode to enforcement mode
    - Include common error scenarios and resolutions
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 5.5_
  
  - [~] 11.5 Update main repository README
    - Edit `aws-service-control-policies/README.md`
    - Add section on AMI Governance policies
    - Link to detailed documentation files
    - Explain Prasa Operations AMI governance approach
    - List approved AMI name patterns
    - _Requirements: 15.1_

- [ ] 12. Create validation and testing scripts
  - [~] 12.1 Create policy structure validation script
    - Create `aws-service-control-policies/scripts/validate-policy-structure.sh`
    - Script validates JSON structure of policy template files
    - Check for required fields (ec2_attributes, allowed_images_settings)
    - Validate template variable syntax
    - Check for common JSON errors
    - Make script executable
    - _Requirements: 4.1_
  
  - [~] 12.2 Create effective policy check script
    - Create `aws-service-control-policies/scripts/check-effective-policy.sh`
    - Accept account ID as parameter
    - Run describe-effective-policy for both policy types
    - Parse and display effective policy in readable format
    - Highlight key settings (enforcement mode, allowed accounts)
    - Make script executable
    - _Requirements: 11.1, 11.2, 11.3_
  
  - [~] 12.3 Create exception expiry check script
    - Create `aws-service-control-policies/scripts/check-exception-expiry.sh`
    - Parse exception_accounts from environment configurations
    - Calculate days until expiry for each exception
    - List active exceptions with days remaining
    - Warn about exceptions expiring within 30 days
    - List expired exceptions
    - Make script executable
    - _Requirements: 17.1, 17.2, 17.3_
  
  - [~] 12.4 Create CloudTrail query helper script
    - Create `aws-service-control-policies/scripts/query-ami-governance-events.sh`
    - Query CloudTrail for RunInstances events
    - Filter for AMI governance policy evaluations
    - Display imageAllowed indicators in audit mode
    - Display AccessDenied events in enforcement mode
    - Accept date range parameters
    - Make script executable
    - _Requirements: 13.1, 13.2, 13.3, 13.5_

- [ ] 13. Prepare for production deployment
  - [~] 13.1 Review production configuration
    - Review `environments/prd/main.tf` for correctness
    - Verify Prasa Operations account IDs: 565656565656, 666363636363
    - Verify target_ids point to correct production OUs (workloads, sandbox)
    - Verify enforcement_mode is "audit_mode" for initial rollout
    - Verify exception_accounts is empty (no exceptions initially)
    - Verify tags are correct for production
    - _Requirements: 1.1, 1.2, 5.1, 7.2, 7.3, 12.1_
  
  - [~] 13.2 Run pre-deployment validation
    - Run `terraform init` in environments/prd
    - Run `terraform validate` to check syntax
    - Run `terraform plan` and save output
    - Review plan output carefully for unexpected changes
    - Verify only new policies and attachments will be created
    - Run policy structure validation script
    - _Requirements: 9.1, 9.2, 9.7_
  
  - [~] 13.3 Create deployment checklist
    - Document all pre-deployment validation steps
    - Document deployment command sequence
    - Document post-deployment validation steps
    - Document rollback procedure if needed
    - Get approval from Cloud Platform Team
    - Schedule deployment window
    - _Requirements: 12.1, 12.2_

- [ ] 14. Deploy to production in audit mode
  - [~] 14.1 Execute production deployment
    - Run `terraform apply` in environments/prd
    - Verify both policies created successfully
    - Verify policy attachments created for all target OUs
    - Save policy IDs from terraform output
    - Document deployment timestamp
    - _Requirements: 9.7, 9.8, 12.1_
  
  - [~] 14.2 Validate production deployment
    - Verify policies exist in AWS Organizations console
    - Check policy content matches expected configuration
    - Run describe-effective-policy for sample production accounts
    - Verify account IDs are correct (565656565656, 666363636363)
    - Verify enforcement state is "audit_mode"
    - Run effective policy check script on multiple accounts
    - _Requirements: 11.1, 11.2, 11.3, 11.4_
  
  - [~] 14.3 Set up CloudTrail monitoring
    - Configure CloudTrail log query for RunInstances events
    - Set up daily monitoring for imageAllowed indicators
    - Create dashboard or report for non-compliant AMI usage
    - Document monitoring process
    - _Requirements: 13.1, 13.2, 13.4_
  
  - [~] 14.4 Monitor audit mode for 2-4 weeks
    - Query CloudTrail logs daily using query helper script
    - Identify any non-compliant AMI usage (imageAllowed=false)
    - Document impacted workloads and teams
    - Work with teams to migrate to approved AMIs or request exceptions
    - Track progress toward full compliance
    - _Requirements: 5.2, 5.4, 12.3, 13.2_

- [ ] 15. Process exception requests (if needed)
  - [~] 15.1 Review exception requests
    - Check Jira for submitted exception requests
    - Verify business justification is provided
    - Verify security approval is obtained
    - Verify requested duration is within limits (365 days for exception AMIs, 90 days for others)
    - _Requirements: 15.2, 15.3, 15.4, 15.5_
  
  - [~] 15.2 Add approved exceptions to configuration
    - Edit `environments/prd/main.tf`
    - Add exception account to exception_accounts map in both module invocations
    - Use format: `"<account-id>" = "<YYYY-MM-DD>"`
    - Add comment with exception reason and ticket number
    - _Requirements: 3.1, 3.2_
  
  - [~] 15.3 Deploy exception updates
    - Run `terraform plan` and verify exception account added to allowlist
    - Run `terraform apply` to update policies
    - Verify policies updated with new exception account
    - Notify requester that exception is active
    - _Requirements: 3.2, 3.6, 10.3_

- [ ] 16. Switch to enforcement mode
  - [~] 16.1 Verify compliance readiness
    - Review CloudTrail logs from audit mode period
    - Confirm all non-compliant usage has been addressed
    - Confirm all necessary exceptions have been granted
    - Get approval from Cloud Platform Team to enable enforcement
    - _Requirements: 5.2, 5.4, 12.4_
  
  - [~] 16.2 Update enforcement mode in production
    - Edit `environments/prd/main.tf`
    - Change `enforcement_mode` from "audit_mode" to "enabled" in declarative policy policy_vars
    - Add comment documenting enforcement mode change and date
    - Run `terraform plan` and verify only policy content changes (no resource recreation)
    - _Requirements: 5.3, 5.5_
  
  - [~] 16.3 Apply enforcement mode change
    - Run `terraform apply` to update declarative policy
    - Verify policy state field changed to "enabled"
    - Verify no errors during apply
    - Document enforcement mode activation timestamp
    - _Requirements: 5.3, 9.7_
  
  - [~] 16.4 Validate enforcement mode
    - Attempt to launch EC2 instance with approved AMI (should succeed)
    - Attempt to launch EC2 instance with non-approved AMI (should be denied)
    - Verify error message shows custom exception_message
    - Verify CloudTrail logs show AccessDenied events for blocked launches
    - Run enforcement validation on multiple accounts
    - _Requirements: 1.3, 1.4, 5.3, 8.2, 13.3_
  
  - [~] 16.5 Monitor enforcement mode
    - Monitor CloudTrail for AccessDenied events
    - Track blocked launch attempts
    - Respond to user questions about blocked launches
    - Process additional exception requests as needed
    - _Requirements: 13.3, 13.5_

- [~] 17. Checkpoint - Production deployment complete
  - Verify policies deployed to production
  - Verify audit mode monitoring completed
  - Verify enforcement mode activated
  - Verify monitoring and alerting in place
  - Document deployment completion
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 18. Optional: Create architecture diagram
  - [ ] 18.1 Create enforcement flow diagram
    - Create diagram showing dual-layer enforcement (Declarative + SCP)
    - Show Prasa Operations accounts as AMI publishers
    - Show target OUs (workloads, sandbox)
    - Show enforcement decision flow
    - Save as `aws-service-control-policies/docs/ami-governance-architecture.png`
    - _Requirements: Design documentation_
  
  - [ ] 18.2 Create exception lifecycle diagram
    - Create diagram showing exception request process
    - Show exception approval workflow
    - Show exception expiry and renewal process
    - Save as `aws-service-control-policies/docs/ami-exception-lifecycle.png`
    - _Requirements: 15.1_

- [ ] 19. Optional: Implement property-based tests
  - [ ] 19.1 Set up property testing framework
    - Choose property testing framework (Hypothesis for Python, gopter for Go)
    - Create test directory structure
    - Set up test fixtures and helpers
    - Configure minimum 100 iterations per test
    - _Requirements: Testing Strategy_
  
  - [ ] 19.2 Write property test for allowlist construction
    - **Property 22: Allowlist combines all publisher sources**
    - Generate random ops_accounts, vendor_accounts, exception_accounts
    - Verify all accounts appear in final allowlist
    - Test with various combinations and edge cases
    - _Requirements: 10.1_
  
  - [ ] 19.3 Write property test for allowlist sorting
    - **Property 23: Allowlist is sorted alphabetically**
    - Generate random account ID lists
    - Verify output is always sorted in ascending order
    - Test with duplicate accounts (should be deduplicated)
    - _Requirements: 10.2_
  
  - [ ] 19.4 Write property test for exception expiry logic
    - **Property 5: Active exceptions included in allowlist**
    - **Property 6: Expired exceptions excluded from allowlist**
    - Generate random exception accounts with various dates
    - Test with dates before, on, and after current date
    - Verify correct filtering based on expiry date
    - _Requirements: 3.2, 3.3_
  
  - [ ] 19.5 Write property test for policy consistency
    - **Property 25: Both policies use identical allowlist**
    - Generate random configurations
    - Parse both policy JSON outputs
    - Verify account lists match exactly
    - _Requirements: 10.4_
  
  - [ ] 19.6 Write property test for tag merging
    - **Property 28: Custom and default tags are merged**
    - Generate random custom tag sets
    - Verify final tags include both custom and default tags
    - Verify no tag key conflicts
    - _Requirements: 14.6_

- [ ] 20. Optional: CI/CD pipeline integration
  - [ ] 20.1 Add validation stage to CI pipeline
    - Update `.gitlab-ci.yml` or equivalent
    - Add stage to run terraform init and validate
    - Add stage to run policy structure validation script
    - Fail pipeline on validation errors
    - _Requirements: 9.1, 9.2_
  
  - [ ] 20.2 Add plan stage to CI pipeline
    - Add stage to run terraform plan for each environment
    - Save plan artifacts
    - Display plan summary in pipeline output
    - Require manual review before apply
    - _Requirements: 9.7_
  
  - [ ] 20.3 Add manual apply stage to CI pipeline
    - Add stage to run terraform apply
    - Require manual approval
    - Only run on main/master branch
    - Use saved plan artifact
    - Send notifications on success/failure
    - _Requirements: 9.7, 9.8_
  
  - [ ] 20.4 Add automated testing stage
    - Run property-based tests in CI
    - Run policy structure validation
    - Run exception expiry checks
    - Fail pipeline if any tests fail
    - _Requirements: Testing Strategy_

- [ ] 21. Final validation and handoff
  - [ ] 21.1 Verify all policies deployed correctly
    - Check AWS Organizations console for both policies in all environments
    - Verify policies attached to correct OUs
    - Verify policy content matches templates
    - Run effective policy checks on sample accounts from each OU
    - _Requirements: 7.5, 11.1, 11.2_
  
  - [ ] 21.2 Verify enforcement working as expected
    - Test approved AMI launch in production (should succeed)
    - Test non-approved AMI launch in production (should be denied)
    - Test AMI creation attempt (should be denied)
    - Test public sharing attempt (should be denied)
    - Verify error messages are clear and helpful
    - _Requirements: 1.3, 1.4, 4.6, 4.7, 6.2, 8.2_
  
  - [ ] 21.3 Verify monitoring and operations
    - Verify CloudTrail logging is working
    - Verify monitoring scripts work correctly
    - Verify exception expiry validation works
    - Test exception request and approval process
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5_
  
  - [ ] 21.4 Create handoff package
    - Compile all documentation into single package
    - Include deployment guide
    - Include monitoring guide
    - Include operational runbook
    - Include exception request process
    - Include architecture diagrams
    - Provide to Cloud Platform Team and operations team
    - _Requirements: 15.1_
  
  - [ ] 21.5 Conduct knowledge transfer session
    - Schedule session with operations team
    - Walk through architecture and design decisions
    - Demonstrate monitoring and troubleshooting
    - Review exception request process
    - Answer questions and document feedback
    - _Requirements: 15.1_

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation at key milestones
- Implementation works within existing `aws-service-control-policies` repository
- No new Terraform modules needed - uses existing `modules/organizations/`
- Policy content managed through JSON template files in `policies/` directory with date stamps
- Template-based policy generation using `templatefile()` function for dynamic content
- Focus on updating existing files rather than creating new infrastructure
- Phased rollout: dev environment → production audit mode → production enforcement mode
- Exception expiry feature already exists in module, just needs to be enabled and configured
- All policy updates use template variables for maintainability and version control
- Dual-layer enforcement (Declarative Policy + SCP) provides defense-in-depth
- Audit mode allows 2-4 weeks of monitoring before full enforcement
- CloudTrail logging provides audit trail for all policy evaluations
- Exception management includes automatic expiry validation to enforce time-bound exceptions
