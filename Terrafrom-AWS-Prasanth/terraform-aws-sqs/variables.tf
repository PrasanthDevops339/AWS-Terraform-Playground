###############################################################################
# Required
###############################################################################

variable "queue_name" {
  description = "Name of the SQS queue. Will be prefixed with the account alias."
  type        = string

  validation {
    condition     = length(var.queue_name) >= 3 && length(var.queue_name) <= 80
    error_message = "queue_name must be between 3 and 80 characters."
  }
}

###############################################################################
# Queue behaviour
###############################################################################

variable "visibility_timeout_seconds" {
  description = "The visibility timeout for the queue, in seconds (0–43200)."
  type        = number
  default     = 30
}

variable "message_retention_seconds" {
  description = "The number of seconds SQS retains a message (60–1209600). Default is 4 days."
  type        = number
  default     = 345600
}

variable "receive_wait_time_seconds" {
  description = "Long-polling wait time in seconds (0–20). 0 disables long polling."
  type        = number
  default     = 0
}

variable "max_message_size" {
  description = "The limit of how many bytes a message can contain before SQS rejects it (1024–262144)."
  type        = number
  default     = 262144
}

variable "delay_seconds" {
  description = "The time in seconds that the delivery of all messages in the queue is delayed (0–900)."
  type        = number
  default     = 0
}

###############################################################################
# Encryption at rest
###############################################################################

variable "kms_master_key_id" {
  description = "The ID/ARN/alias of an AWS KMS key to use for server-side encryption. Leave null for SQS-managed encryption (SSE-SQS)."
  type        = string
  default     = null
}

variable "kms_data_key_reuse_period_seconds" {
  description = "The length of time in seconds for which SQS can reuse a data key to encrypt/decrypt messages (60–86400). Only relevant when kms_master_key_id is set."
  type        = number
  default     = 300
}

###############################################################################
# Dead letter queue
###############################################################################

variable "enable_dlq" {
  description = "Create a dead letter queue and configure a redrive policy on the main queue."
  type        = bool
  default     = false
}

variable "dlq_message_retention_seconds" {
  description = "Message retention period for the DLQ in seconds. Default is 14 days."
  type        = number
  default     = 1209600
}

variable "max_receive_count" {
  description = "The number of times a consumer tries to receive and process a message before it is sent to the DLQ."
  type        = number
  default     = 3
}

###############################################################################
# In-transit security
###############################################################################

variable "enable_secure_transport" {
  description = "Attach a queue policy that explicitly denies any request not using TLS (aws:SecureTransport=false). Safe to enable — AWS SDKs use HTTPS by default."
  type        = bool
  default     = false
}

###############################################################################
# Tags
###############################################################################

variable "tags" {
  description = "A map of additional tags to apply to all resources created by this module."
  type        = map(string)
  default     = {}
}
