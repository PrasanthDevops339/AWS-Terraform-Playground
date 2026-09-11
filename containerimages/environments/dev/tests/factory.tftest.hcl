mock_provider "aws" {
  mock_resource "aws_imagebuilder_component" {
    defaults = { arn = "arn:aws:imagebuilder:us-east-2:123456789012:component/mock/1.0.0/1" }
  }
  mock_resource "aws_imagebuilder_container_recipe" {
    defaults = { arn = "arn:aws:imagebuilder:us-east-2:123456789012:container-recipe/mock/1.0.0" }
  }
  mock_resource "aws_imagebuilder_infrastructure_configuration" {
    defaults = { arn = "arn:aws:imagebuilder:us-east-2:123456789012:infrastructure-configuration/mock" }
  }
  mock_resource "aws_imagebuilder_distribution_configuration" {
    defaults = { arn = "arn:aws:imagebuilder:us-east-2:123456789012:distribution-configuration/mock" }
  }
  mock_resource "aws_imagebuilder_image_pipeline" {
    defaults = { arn = "arn:aws:imagebuilder:us-east-2:123456789012:image-pipeline/mock" }
  }
  mock_resource "aws_cloudwatch_event_rule" {
    defaults = { arn = "arn:aws:events:us-east-2:123456789012:rule/mock" }
  }
  mock_resource "aws_codebuild_project" {
    defaults = { arn = "arn:aws:codebuild:us-east-2:123456789012:project/mock" }
  }
  mock_resource "aws_dynamodb_table" {
    defaults = { arn = "arn:aws:dynamodb:us-east-2:123456789012:table/mock" }
  }
  mock_resource "aws_sfn_state_machine" {
    defaults = { arn = "arn:aws:states:us-east-2:123456789012:stateMachine:mock" }
  }
  mock_resource "aws_ecr_repository" {
    defaults = { arn = "arn:aws:ecr:us-east-2:123456789012:repository/mock" }
  }

  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock-role" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:us-east-2:123456789012:function:mock" }
  }
  mock_resource "aws_sqs_queue" {
    defaults = { arn = "arn:aws:sqs:us-east-2:123456789012:mock-queue", id = "https://sqs.us-east-2.amazonaws.com/123456789012/mock-queue" }
  }
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:us-east-2:123456789012:mock-topic" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::mock-evidence" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-2:123456789012:log-group:mock" }
  }

  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-2:123456789012:key/11111111-1111-1111-1111-111111111111" }
  }
}
mock_provider "aws" {
  mock_resource "aws_imagebuilder_component" {
    defaults = { arn = "arn:aws:imagebuilder:us-east-2:123456789012:component/mock/1.0.0/1" }
  }
  mock_resource "aws_imagebuilder_container_recipe" {
    defaults = { arn = "arn:aws:imagebuilder:us-east-2:123456789012:container-recipe/mock/1.0.0" }
  }
  mock_resource "aws_imagebuilder_infrastructure_configuration" {
    defaults = { arn = "arn:aws:imagebuilder:us-east-2:123456789012:infrastructure-configuration/mock" }
  }
  mock_resource "aws_imagebuilder_distribution_configuration" {
    defaults = { arn = "arn:aws:imagebuilder:us-east-2:123456789012:distribution-configuration/mock" }
  }
  mock_resource "aws_imagebuilder_image_pipeline" {
    defaults = { arn = "arn:aws:imagebuilder:us-east-2:123456789012:image-pipeline/mock" }
  }
  mock_resource "aws_cloudwatch_event_rule" {
    defaults = { arn = "arn:aws:events:us-east-2:123456789012:rule/mock" }
  }
  mock_resource "aws_codebuild_project" {
    defaults = { arn = "arn:aws:codebuild:us-east-2:123456789012:project/mock" }
  }
  mock_resource "aws_dynamodb_table" {
    defaults = { arn = "arn:aws:dynamodb:us-east-2:123456789012:table/mock" }
  }
  mock_resource "aws_sfn_state_machine" {
    defaults = { arn = "arn:aws:states:us-east-2:123456789012:stateMachine:mock" }
  }
  mock_resource "aws_ecr_repository" {
    defaults = { arn = "arn:aws:ecr:us-east-2:123456789012:repository/mock" }
  }

  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock-role" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:us-east-2:123456789012:function:mock" }
  }
  mock_resource "aws_sqs_queue" {
    defaults = { arn = "arn:aws:sqs:us-east-2:123456789012:mock-queue", id = "https://sqs.us-east-2.amazonaws.com/123456789012/mock-queue" }
  }
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:us-east-2:123456789012:mock-topic" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::mock-evidence" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-2:123456789012:log-group:mock" }
  }

  alias = "replica"
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/22222222-2222-2222-2222-222222222222" }
  }
}
variables {
  access_log_bucket_name  = "test-access-logs"
  name                    = "test-factory"
  account_id              = "123456789012"
  organization_id         = "o-abcdefghij"
  vpc_id                  = "vpc-0123456789abcdef0"
  subnet_id               = "subnet-0123456789abcdef0"
  egress_cidrs            = ["10.0.0.0/16"]
  build_host_ami          = "ami-0123456789abcdef0"
  parent_image            = "public.ecr.aws/amazonlinux/amazonlinux@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  source_revision         = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  package_release         = "2023.8.20250818"
  certificate_bundle      = "../../tests/fixtures/ca.pem"
  package_repository_file = "../../tests/fixtures/enterprise.repo"
  promotion_worker_image  = "123456789012.dkr.ecr.us-east-2.amazonaws.com/trusted-worker@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
}
run "factory_is_isolated_and_gate_is_enforced" {
  command = apply
  module { source = "../../modules/factory" }
  providers = { aws = aws, aws.replica = aws.replica }
  assert {
    condition     = length(aws_ecr_registry_scanning_configuration.primary) == 0 && length(aws_ecr_replication_configuration.approved) == 0
    error_message = "Shared registry settings must require explicit ownership."
  }
  assert {
    condition     = aws_imagebuilder_image_pipeline.al2023.image_tests_configuration[0].image_tests_enabled && aws_imagebuilder_infrastructure_configuration.al2023.terminate_instance_on_failure
    error_message = "Build tests and failed-instance cleanup are required."
  }
  assert {
    condition     = !aws_codebuild_project.promotion.environment[0].privileged_mode && strcontains(aws_imagebuilder_container_recipe.al2023.dockerfile_template_data, "USER 10001:10001")
    error_message = "The publisher must not run privileged containers and the output must default to non-root."
  }
  assert {
    condition     = jsondecode(aws_sfn_state_machine.release.definition).States.GateResult.Default == "Rejected" && jsondecode(aws_sfn_state_machine.release.definition).States.GateResult.Choices[0].Next == "Promote"
    error_message = "Only ACCEPTED candidates may reach promotion."
  }
  assert {
    condition     = alltrue([for statement in jsondecode(aws_iam_role_policy.builder.policy).Statement : !contains(try(tolist(statement.Action), []), "ecr:PutImage") || statement.Resource == "arn:aws:ecr:us-east-2:123456789012:repository/staging/test-factory/al2023-base"])
    error_message = "Builder publication must be limited to staging."
  }
  assert {
    condition     = aws_dynamodb_table.releases.deletion_protection_enabled && aws_dynamodb_table.releases.point_in_time_recovery[0].enabled
    error_message = "Protect the version ledger from accidental loss."
  }
}
run "reject_floating_base_tag" {
  command = plan
  module { source = "../../modules/factory" }
  providers = { aws = aws, aws.replica = aws.replica }
  variables { parent_image = "public.ecr.aws/amazonlinux/amazonlinux:2023" }
  expect_failures = [var.parent_image]
}
run "reject_unrestricted_egress" {
  command = plan
  module { source = "../../modules/factory" }
  providers = { aws = aws, aws.replica = aws.replica }
  variables { egress_cidrs = ["0.0.0.0/0"] }
  expect_failures = [var.egress_cidrs]
}

