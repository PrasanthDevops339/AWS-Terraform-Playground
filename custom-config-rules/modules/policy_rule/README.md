## Providers

| Name | Version |
|------|---------|

## Resources

| Name | Type | Version |
|------|------|---------|
| [aws_config_organization_custom_policy_rule.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/config_organization_custom_policy_rule) | resource | N/A |
| [aws_config_config_rule.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/config_config_rule) | resource | N/A |
| [aws_iam_account_alias.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_account_alias) | data | N/A |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| config_rule_name | Name of the config rule | string | N/A | yes |
| config_rule_version | Calendar version of the config rule you want to deploy | string | N/A | yes |
| description | Description of the rule | string | N/A | yes |
| trigger_types | List of notification types that trigger the rule to run an evaluation | list(string) | ["ConfigurationItemChangeNotification"] | no |
| message_type | Notification types that trigger the rule to run an evaluation | string | "ConfigurationItemChangeNotification" | no |
| create_config_rule | Boolean to toggle the rule on and off | bool | true | no |
| excluded_accounts | List of excluded accounts | list(string) | [] | no |
| resource_types_scope | List of resources types in the scope of the rule | list(string) | [] | no |
| organization_rule | N/A | bool | false | no |
| random_id | Pass in the random id here to append to resource that is created. | string | null | no |

## Outputs

| Name | Description |
|------|-------------|
| rule_id | N/A |
