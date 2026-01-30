resource "aws_sns_topic" "db_instance_alert" {
  name = "mysql-db-event-alert-${random_string.module_id.result}"
  tags = merge({ Name = "mysql-db-event-alert" })
}

resource "aws_sns_topic_subscription" "db_instance_alert" {
  topic_arn = aws_sns_topic.db_instance_alert.arn
  protocol  = "email"
  endpoint  = "cloud_ops_dl@test-placeholder.com"
}
