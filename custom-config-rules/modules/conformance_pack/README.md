## Providers

| Name | Version |
|------|---------|

## Resources

| Name | Type | Version |
|------|------|---------|
| [aws_config_conformance_pack.encryption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/config_conformance_pack) | resource | N/A |
| [aws_iam_account_alias.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_account_alias) | data | N/A |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data | N/A |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data | N/A |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cpack_name | Name of the conformance pack | string | n/a | yes |
| policy_rules_list | List of resources types in the scope of the rule | <pre>list(object({
  config_rule_name    = string
  config_rule_version = string
  description         = string
  policy_runtime      = optional(string, "guard-2.x.x")
  resource_types_scope = list(string)
}))</pre> | `[]` | no |
| organization_pack | Set to true if you want this conformance pack to be deployed across the organization. | bool | `false` | no |
| excluded_accounts | List of excluded accounts that the pack will not deploy to in the organization | list(string) | `[]` | no |
| random_id | Pass in the random id here to append to resource that is created. | string | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| template_yml | N/A |
