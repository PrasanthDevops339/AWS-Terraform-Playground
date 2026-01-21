
#------------------------------
# LAMBDA FUNCTION - S3 Resources - event trigger
#------------------------------

# Creates S3 bucket event notification to trigger lambda function
resource "aws_s3_bucket_notification" "bucket_notification" {
  count  = var.create_lambda_function && var.create_bucket_event_trigger ? 1 : 0
  bucket = var.lambda_trigger_bucket_name

  lambda_function {
    id                  = "S3BucketEventInvoke"
    lambda_function_arn = local.lambda_arn
    events              = var.lambda_trigger_bucket_events
    filter_prefix       = var.lambda_trigger_bucket_object_prefix
    filter_suffix       = var.lambda_trigger_bucket_object_suffix
  }
}

# Creates permission that allow s3 bucket event to invoke the lambda function
resource "aws_lambda_permission" "s3invoke" {
  count = var.create_lambda_function && var.create_bucket_event_trigger ? 1 : 0

  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = local.lambda_arn
  principal     = "s3.amazonaws.com"
  source_arn    = var.lambda_trigger_bucket_arn
}
