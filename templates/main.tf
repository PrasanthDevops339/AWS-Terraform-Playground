# Main resource configuration goes here
resource "aws_example_resource" "main" {
  # Resource configuration

  tags = merge(
    var.tags,
    {
      Name = "example-resource"
    }
  )
}