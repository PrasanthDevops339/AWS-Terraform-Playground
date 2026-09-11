resource "aws_security_group" "builder" {
  name        = "${var.name}-builder"
  description = "Private Image Builder instances; no inbound access"
  vpc_id      = var.vpc_id
}
resource "aws_vpc_security_group_egress_rule" "https" {
  for_each          = var.egress_cidrs
  security_group_id = aws_security_group.builder.id
  description       = "Approved HTTPS build dependencies"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}
resource "aws_imagebuilder_component" "baseline" {
  name       = "${var.name}-al2023-baseline"
  platform   = "Linux"
  version    = var.recipe_version
  kms_key_id = aws_kms_key.primary.arn
  data = yamlencode({
    name = "AL2023EnterpriseBaseline", description = "Apply the reviewed AL2023 container baseline", schemaVersion = "1.0"
    phases = [{ name = "build", steps = [{ name = "Baseline", action = "ExecuteBash", onFailure = "Abort",
      inputs = { commands = [templatefile("${path.module}/../../components/al2023-build.sh.tftpl", {
        ca_base64       = filebase64(var.certificate_bundle), repo_base64 = filebase64(var.package_repository_file),
        package_release = var.package_release, parent_image = var.parent_image,
        source_revision = var.source_revision, recipe_version = var.recipe_version
      })] }
    }] }]
  })
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_imagebuilder_component" "tests" {
  name       = "${var.name}-al2023-tests"
  platform   = "Linux"
  version    = var.recipe_version
  kms_key_id = aws_kms_key.primary.arn
  data = yamlencode({
    name = "AL2023ContainerTests", description = "OS, certificate, permissions and application smoke checks", schemaVersion = "1.0"
    phases = [{ name = "test", steps = [{ name = "ValidateContainer", action = "ExecuteBash", onFailure = "Abort",
      inputs = { commands = [file("${path.module}/../../components/al2023-test.sh")] }
    }] }]
  })
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_imagebuilder_container_recipe" "al2023" {
  name              = "${var.name}-al2023"
  version           = var.recipe_version
  container_type    = "DOCKER"
  parent_image      = var.parent_image
  platform_override = "Linux"
  kms_key_id        = aws_kms_key.primary.arn
  working_directory = "/tmp/imagebuilder"
  target_repository {
    repository_name = module.staging.name
    service         = "ECR"
  }
  component {
    component_arn = aws_imagebuilder_component.baseline.arn
  }
  component {
    component_arn = aws_imagebuilder_component.tests.arn
  }
  instance_configuration {
    image = var.build_host_ami
    block_device_mapping {
      device_name = "/dev/xvda"
      ebs {
        volume_size           = 40
        volume_type           = "gp3"
        encrypted             = true
        delete_on_termination = true
        kms_key_id            = aws_kms_key.primary.arn
      }
    }
  }
  dockerfile_template_data = <<-DOCKERFILE
    FROM {{{ imagebuilder:parentImage }}}
    {{{ imagebuilder:environments }}}
    {{{ imagebuilder:components }}}
    LABEL org.opencontainers.image.title="Enterprise AL2023 base" \
          org.opencontainers.image.revision="${var.source_revision}" \
          org.opencontainers.image.base.name="${var.parent_image}"
    WORKDIR /app
    USER 10001:10001
    CMD ["/bin/bash"]
  DOCKERFILE
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_imagebuilder_infrastructure_configuration" "al2023" {
  name                          = "${var.name}-al2023"
  instance_profile_name         = aws_iam_instance_profile.builder.name
  instance_types                = ["m6i.large"]
  subnet_id                     = var.subnet_id
  security_group_ids            = [aws_security_group.builder.id]
  terminate_instance_on_failure = true
  instance_metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }
  logging {
    s3_logs {
      s3_bucket_name = aws_s3_bucket.evidence.id
      s3_key_prefix  = "build-logs"
    }
  }
  resource_tags = merge(var.tags, { Factory = var.name })
  depends_on    = [aws_iam_role_policy.builder, aws_iam_role_policy_attachment.builder_core, aws_iam_role_policy_attachment.builder_ssm]
}
resource "aws_imagebuilder_distribution_configuration" "staging" {
  #checkov:skip=CKV_AWS_199:Container distribution has no AMI encryption setting; ECR repositories use regional customer-managed KMS keys.

  name = "${var.name}-candidates"
  distribution {
    region = var.primary_region
    container_distribution_configuration {
      target_repository {
        repository_name = module.staging.name
        service         = "ECR"
      }
      container_tags = ["candidate-${var.recipe_version}-{{imagebuilder:buildVersion}}"]
    }
  }
}
resource "aws_imagebuilder_image_pipeline" "al2023" {
  name                             = "${var.name}-al2023"
  container_recipe_arn             = aws_imagebuilder_container_recipe.al2023.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.al2023.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.staging.arn
  status                           = "ENABLED"
  image_tests_configuration {
    image_tests_enabled = true
    timeout_minutes     = 60
  }
  dynamic "schedule" {
    for_each = var.schedule_enabled ? [1] : []
    content {
      schedule_expression                = "cron(0 6 ? * MON *)"
      pipeline_execution_start_condition = "EXPRESSION_MATCH_ONLY"
    }
  }
}
