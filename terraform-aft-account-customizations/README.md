
# terraform-aft-account-customizations (sample slice)

This zip contains:
- `modules/lambda` : Lambda Terraform module (Zip or Image, optional triggers)
- `modules/scripts/backup-tags` : Python AWS Config custom rule logic + JSON parameters
- `exceptions/terraform/tagging-enforcement.tf` : Example wiring of the Lambda as an AWS Config CUSTOM_LAMBDA rule

Note:
- Update `backup_tags.json` to your full allowed tag lists as needed.
- Ensure AWS Config recorder is enabled in the target account/region.
