################################################################################
# Service Connect with TLS
#
# Service Connect gives service-to-service traffic a stable DNS name, per-request
# routing, retries and metrics, via a sidecar proxy ECS injects for you. Adding
# a `tls` block makes ECS issue and rotate certificates from AWS Private CA and
# encrypt that traffic in transit, without the application handling certs.
#
# Two services:
#
#   api  the SERVER. Advertises port "http" into the namespace under the
#        discovery name "api", with TLS enabled.
#   web  the CLIENT. Enables Service Connect but advertises nothing, so it can
#        resolve and call http://api:8080 over the encrypted mesh.
#
# The asymmetry is the point: a client-only service sets enabled = true and
# omits `services` entirely.
################################################################################

locals {
  # Service Connect requires NAMED port mappings - the name is what
  # services[].port_name refers to. An unnamed mapping silently fails to
  # register.
  api_port_mappings = [
    {
      name          = "http"
      containerPort = var.api_container_port
      protocol      = "tcp"
      appProtocol   = "http"
    },
  ]
}

module "ecs_service_connect" {
  source = "../../"

  cluster_name = var.cluster_name
  vpc_id       = var.vpc_id
  tags         = var.tags

  load_balanced = false
  target_groups = []

  # Sets the cluster-wide default namespace, so services that omit `namespace`
  # still land in the right mesh.
  service_connect_configuration = {
    enabled   = true
    namespace = var.service_connect_namespace_arn
  }

  container_config = {

    ##########################################################################
    # api - the server side
    ##########################################################################
    api = {
      container_name = "api"

      task_definition = {
        cpu                 = 512
        memory              = 1024
        image               = var.api_image
        execution_role_arn  = var.execution_role_arn
        task_role_arn       = var.api_task_role_arn
        task_log_group_name = "/ecs/${var.cluster_name}/api"
        port_mappings       = local.api_port_mappings
      }

      service = {
        desired_count   = 2
        subnets         = var.subnet_ids
        security_groups = [var.api_security_group_id]

        service_connect = {
          enabled   = true
          namespace = var.service_connect_namespace_arn

          # Logs from the injected Envoy sidecar. Worth enabling: without it,
          # mesh-level failures are invisible and look like application bugs.
          log_configuration = {
            log_driver = "awslogs"
            options = {
              "awslogs-group"         = var.service_connect_log_group_name
              "awslogs-region"        = var.aws_region
              "awslogs-stream-prefix" = "service-connect"
            }
          }

          services = [
            {
              # Must match a NAME in the task definition's port_mappings.
              port_name = "http"

              # The name other services resolve within the namespace.
              discovery_name = "api"

              client_aliases = [
                {
                  dns_name = "api"
                  port     = var.api_container_port
                },
              ]

              # ---- TLS ----
              # ECS requests a short-lived certificate from Private CA for each
              # task and rotates it. The application keeps serving plain HTTP;
              # the sidecar terminates TLS.
              tls = {
                issuer_cert_authority = {
                  aws_pca_authority_arn = var.private_ca_arn
                }

                # Role ECS assumes to issue certificates from the CA. Needs
                # acm-pca:IssueCertificate and acm-pca:GetCertificate on the CA,
                # and a trust policy for ecs.amazonaws.com.
                role_arn = var.service_connect_tls_role_arn

                # Optional CMK for the generated private keys. Omit for the
                # AWS-managed key.
                kms_key = var.service_connect_tls_kms_key_arn
              }

              # Fail fast rather than holding connections open when a task is
              # unhealthy.
              timeout = {
                idle_timeout_seconds        = 60
                per_request_timeout_seconds = 15
              }
            },
          ]
        }
      }

      autoscaling = {
        min_capacity                     = 2
        max_capacity                     = 10
        cpu_scaling_policy_configuration = { target_value = 60 }
      }

      alarms = {
        enabled        = true
        sns_topic_arns = var.alarm_sns_topic_arns
      }
    }

    ##########################################################################
    # web - the client side
    #
    # Note there is no `services` list. A client-only service joins the mesh so
    # it can resolve other services, but advertises nothing itself.
    ##########################################################################
    web = {
      container_name = "web"

      task_definition = {
        cpu                = 512
        memory             = 1024
        image              = var.web_image
        execution_role_arn = var.execution_role_arn
        task_role_arn      = var.web_task_role_arn

        task_log_group_name = "/ecs/${var.cluster_name}/web"

        # Reaches the api over the mesh by its client alias. Traffic leaves the
        # container as plain HTTP and is encrypted by the sidecar.
        environment = [
          {
            name  = "API_ENDPOINT"
            value = "http://api:${var.api_container_port}"
          },
        ]

        port_mappings = [
          {
            name          = "http"
            containerPort = var.web_container_port
            protocol      = "tcp"
            appProtocol   = "http"
          },
        ]
      }

      service = {
        desired_count   = 2
        subnets         = var.subnet_ids
        security_groups = [var.web_security_group_id]

        service_connect = {
          enabled   = true
          namespace = var.service_connect_namespace_arn

          log_configuration = {
            log_driver = "awslogs"
            options = {
              "awslogs-group"         = var.service_connect_log_group_name
              "awslogs-region"        = var.aws_region
              "awslogs-stream-prefix" = "service-connect"
            }
          }
        }
      }

      autoscaling = {
        min_capacity                     = 2
        max_capacity                     = 10
        cpu_scaling_policy_configuration = { target_value = 60 }
      }

      alarms = {
        enabled        = true
        sns_topic_arns = var.alarm_sns_topic_arns
      }
    }
  }
}
