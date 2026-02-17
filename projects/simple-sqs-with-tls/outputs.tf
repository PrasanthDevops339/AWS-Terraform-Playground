###############################################################################
# Outputs
###############################################################################

# SQS Main Queue
output "queue_url" {
  description = "URL of the SQS queue — use this in SDK/CLI calls"
  value       = module.sqs.queue_url
}

output "queue_arn" {
  description = "ARN of the SQS queue"
  value       = module.sqs.queue_arn
}

output "queue_name" {
  description = "Name of the SQS queue as it appears in AWS"
  value       = module.sqs.queue_name
}

# SQS Dead Letter Queue
output "dlq_url" {
  description = "URL of the dead letter queue"
  value       = module.sqs.dlq_url
}

output "dlq_arn" {
  description = "ARN of the dead letter queue"
  value       = module.sqs.dlq_arn
}

# KMS
output "kms_key_arn" {
  description = "ARN of the KMS key used for SQS encryption at rest"
  value       = module.kms.key_arn
}

# Policy state — should read true here, confirming the policy is active
output "secure_transport_policy_enabled" {
  description = "Whether the SecureTransport deny policy is currently attached"
  value       = module.sqs.secure_transport_policy_enabled
}

# Quick-reference test commands — same as simple-sqs-no-tls, must still work
output "test_send_message" {
  description = "AWS CLI command to send a test message (should succeed — SDK uses HTTPS)"
  value       = "aws sqs send-message --queue-url ${module.sqs.queue_url} --message-body 'hello-with-tls-policy' --region ${data.aws_region.current.name}"
}

output "test_receive_message" {
  description = "AWS CLI command to receive a message (should succeed — SDK uses HTTPS)"
  value       = "aws sqs receive-message --queue-url ${module.sqs.queue_url} --region ${data.aws_region.current.name}"
}

output "verify_policy" {
  description = "AWS CLI command to inspect the attached queue policy"
  value       = "aws sqs get-queue-attributes --queue-url ${module.sqs.queue_url} --attribute-names Policy --region ${data.aws_region.current.name}"
}
