# service-connect-tls

Service Connect with TLS in transit, issued and rotated by ECS from AWS Private
CA.

## What Service Connect gives you

A stable DNS name for service-to-service traffic, plus per-request routing,
retries, timeouts and metrics — via an Envoy sidecar ECS injects into each
task. Adding a `tls` block makes ECS issue a short-lived certificate per task
from Private CA and rotate it.

The application keeps serving plain HTTP. The sidecar terminates TLS. That is
the main reason to reach for this over doing certificates in-app.

## The two sides

| Service | Role | Config |
| --- | --- | --- |
| `api` | Server | `enabled = true` **plus** a `services` list advertising port `http` as discovery name `api`, with `tls` |
| `web` | Client | `enabled = true` and **nothing else** |

That asymmetry is the part people get wrong. A client-only service joins the
mesh so it can resolve others, but advertises nothing itself — so it omits the
`services` list entirely.

`web` then reaches `api` at `http://api:8080`, and the traffic is encrypted
between sidecars.

## Service Connect vs service discovery

Distinct things, easy to conflate:

- **Service Connect** — sidecar proxy, per-request routing, retries, mesh
  metrics, and optional TLS. This example.
- **Cloud Map service discovery** (`service_registries`) — plain DNS records in
  a private hosted zone. No proxy, no retries, no TLS.

## Prerequisites

- an existing Cloud Map **HTTP** namespace (not a DNS namespace)
- an **ACTIVE** AWS Private CA
- an IAM role ECS assumes to issue certificates, with
  `acm-pca:IssueCertificate` and `acm-pca:GetCertificate` on the CA, a trust
  policy for `ecs.amazonaws.com`, and `kms:GenerateDataKey` on the CMK if you
  set one
- VPC and private subnets — Service Connect requires the `awsvpc` network mode
- a CloudWatch log group for the sidecar logs
- task execution role and per-service task role ARNs

## Two things that will cost you an afternoon

**Port mappings must be NAMED.** `services[].port_name` refers to the `name` on
a task definition port mapping. An unnamed mapping silently fails to register
in the namespace, and the client gets DNS resolution failures with nothing
useful in the application logs.

**Enable the sidecar log configuration.** Without it, mesh-level failures —
certificate issuance problems, upstream connection failures, timeout tuning —
are invisible and look like application bugs. Both services here write sidecar
logs with the `service-connect` stream prefix.

## Usage

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Confirm both services registered in the namespace
aws servicediscovery list-services \
  --filters Name=NAMESPACE_ID,Values=<namespace-id>

# Sidecar logs are where mesh problems actually surface
aws logs tail <service_connect_log_group_name> --follow \
  --filter-pattern "service-connect"
```
