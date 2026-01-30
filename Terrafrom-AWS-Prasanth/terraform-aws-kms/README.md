## Overview

Key Management Service (KMS) can be leveraged to create, manage, and control cryptographic keys. This will allow your application to securely encrypt sensitive data.

## Supported features

* Create KMS keys and key aliases
* Create replica keys for multi-region support
* Manage application permissions for keys
* Yearly key rotation
* Flexible deletion window
* Tagging

## Unsupported features

* Asymmetric keys
* External keys
* KMS grants

## Note

* If you are using module version `2.3.11` or lower AND aws provider version `5.X`, please note that you are using deprecated configurations (refer to `deprecated.tf` files for more information)
* If you are using module version `3.0.0` or higher, you must use aws provider version `6.X` or higher to utilize new region configurations

## Examples

* [Examples](https://gitlab.prasanurance.com/tfe-platform/modules/erie-aws/terraform-aws-kms/-/tree/main/examples)

* [Simplest example](https://gitlab.prasanurance.com/tfe-platform/modules/erie-aws/terraform-aws-kms/-/blob/main/examples/simple/main.tf) using default baseline key policy:

```hcl
module "simple_key" {
  source  = "tfe.prasanurance.com/test-placeholder/kms/aws"
  version = "insert version here"

  enable_region_argument = true
  key_name               = "simple-test-${random_string.example_suffix.result}"
}
