# Build a JSON schema of test events for the function (optional)

locals {
  test_events_str_array = [
    for index, test_event in var.test_events :
    templatefile("${path.module}/templates/test_event_template.json", {
      event_name  = test_event.event_name
      event_value = test_event.event_value
      comma       = index < length(var.test_events) - 1 ? "," : ""
    })
  ]

  test_events_str = "${join("", local.test_events_str_array)}"
}

resource "aws_schemas_schema" "test_event_schema" {
  count = length(var.test_events) > 0 ? 1 : 0

  name          = "${element(concat(aws_lambda_function.main.*.function_name, [""]), 0)}-schema"
  registry_name = "lambda-testevent-schemas"
  type          = "OpenApi3"

  content     = templatefile("${path.module}/templates/test_events_template.json", {})
  test_events = local.test_events_str
}
