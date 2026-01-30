# Module version 3.0.0 or higher

resource "random_string" "example_suffix" {
  length  = 6
  numeric = false
  special = false
  upper   = false
}

module "simple_key" {
  source = "../../"

  enable_region_argument = true

  key_name = "simple-test-${random_string.example_suffix.result}"
}
