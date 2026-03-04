###############################################################################
# Main queue outputs
###############################################################################

output "queue_url" {
  description = "The URL of the SQS queue."
  value       = aws_sqs_queue.main.id
}

output "queue_arn" {
  description = "The ARN of the SQS queue."
  value       = aws_sqs_queue.main.arn
}

output "queue_name" {
  description = "The name of the SQS queue as created in AWS."
  value       = aws_sqs_queue.main.name
}

###############################################################################
# Dead letter queue outputs (null when enable_dlq=false)
###############################################################################

output "dlq_url" {
  description = "The URL of the dead letter queue. Null when enable_dlq=false."
  value       = try(aws_sqs_queue.dlq[0].id, null)
}

output "dlq_arn" {
  description = "The ARN of the dead letter queue. Null when enable_dlq=false."
  value       = try(aws_sqs_queue.dlq[0].arn, null)
}

output "dlq_name" {
  description = "The name of the dead letter queue. Null when enable_dlq=false."
  value       = try(aws_sqs_queue.dlq[0].name, null)
}

###############################################################################
# Policy outputs
###############################################################################

output "secure_transport_policy_enabled" {
  description = "Whether the SecureTransport deny policy is attached to the queue."
  value       = var.enable_secure_transport
}

