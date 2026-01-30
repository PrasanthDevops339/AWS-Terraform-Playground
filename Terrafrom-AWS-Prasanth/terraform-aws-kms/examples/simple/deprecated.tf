# Module version 2.3.11 or below

module "deprecated_simple_key" {
  source = "../../"

  key_name = "deprecated-simple-test-${random_string.example_suffix.result}"
}
