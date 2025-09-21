# Module Name

Brief description of what this module does.

## Usage

```hcl
module "example" {
  source = "./modules/module-name"

  example_variable = "value"

  tags = {
    Environment = "development"
    Project     = "terraform-playground"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| aws | ~> 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| example_variable | Description of the variable | `string` | `"default_value"` | no |
| tags | A map of tags to assign to the resource | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| example_output | Description of the output |