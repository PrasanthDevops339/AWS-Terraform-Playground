module "waf_use1" {
  source = "../.."

  create_ip_set                = false
  waf_name                     = "Prasanth-waf-simple-use1-${random_string.suffix.id}"
  scope                        = "REGIONAL"
  region                       = "us-east-1"
  cloudwatch_metrics_enabled   = true
  sampled_requests_enabled     = true
}

module "waf_use2" {
  source = "../.."

  create_ip_set                = false
  waf_name                     = "Prasanth-waf-simple-use2-${random_string.suffix.id}"
  scope                        = "REGIONAL"
  region                       = "us-east-2"
  cloudwatch_metrics_enabled   = true
  sampled_requests_enabled     = true
}

resource "random_string" "suffix" {
  length    = 4
  special   = false
  min_lower = 4
}
