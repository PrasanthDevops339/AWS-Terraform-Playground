resource "random_string" "main" {
  count   = var.add_random_characters == true ? 1 : 0
  length  = 6
  numeric = false
  special = false
}

resource "aws_organizations_policy" "main" {
  count = var.create_policy == true ? 1 : 0

  content = jsonencode(
    jsondecode(
      templatefile(
        "../../policies/${var.policy_name}-${var.file_date}.json",
        var.policy_vars
      )
    )
  )

  name         = var.add_random_characters == true ? "${var.policy_name}-${random_string.main[0].id}" : var.policy_name
  description  = var.description
  skip_destroy = var.skip_destroy
  type         = var.type
  tags         = var.tags
}

resource "aws_organizations_policy_attachment" "main" {
  for_each = var.target_ids

  policy_id    = var.create_policy == true ? aws_organizations_policy.main[0].id : var.policy_id
  target_id    = each.value
  skip_destroy = var.skip_destroy
}
