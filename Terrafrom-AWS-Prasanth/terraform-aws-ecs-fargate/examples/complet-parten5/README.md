# Pattern 5 Complete Example

This example implements Pattern 5 from the user guide:

- target groups only for the edge-facing tier
- Service Connect for internal HTTP calls
- workers with no target groups and no inbound port mappings

The directory name is `complet-parten5` to match the requested example name.

## Services

- `frontend`: edge-facing web tier behind an existing target group
- `api`: private internal HTTP service published only through Service Connect
- `worker`: private background tier with no target group and no inbound port
  mappings

## What It Demonstrates

- one shared Fargate cluster
- external ingress only on the `frontend` tier
- Service Connect client-only usage on `frontend` and `worker`
- Service Connect server plus client aliases on `api`
- worker capacity split across `FARGATE` and `FARGATE_SPOT`
- autoscaling without creating internal ALBs for private services

## Real-World Usage

This pattern is common in software systems where only the presentation tier
should be public, while application logic and background processing stay
private.

Typical app types:

- SaaS web applications: public UI, private API, background jobs for email,
  billing, reporting, or notifications
- e-commerce platforms: storefront behind ALB, private order or catalog API,
  async workers for inventory sync, payment events, and fulfillment tasks
- internal business portals: internet or VPN-facing frontend, private API, and
  background integrations with ERP, CRM, or document systems
- content platforms: public web app, private content API, and workers for media
  processing, indexing, thumbnail generation, or publishing workflows
- B2B applications: customer-facing dashboard, internal service layer, and
  workers for imports, exports, scheduled reconciliation, or event processing

Why teams use Pattern 5 in the real world:

- only the edge tier needs public load balancer exposure
- private services are reachable by stable Service Connect names instead of
  internal ALB DNS names
- worker tiers stay isolated and do not accidentally become network entry
  points
- fewer internal load balancers means lower operational sprawl and simpler
  security-group design
- the boundary between user-facing traffic and service-to-service traffic stays
  explicit

Concrete example:

- `frontend`: React, Angular, Next.js, or server-rendered web app
- `api`: REST, GraphQL, or internal HTTP service used only by trusted tiers
- `worker`: queue consumer, scheduler, event processor, or batch job runner

## External Prerequisites

This example assumes these resources already exist:

- VPC and private subnet IDs
- security groups for all three tiers
- execution and task roles for all three tiers
- Cloud Map namespace ARN for Service Connect
- CloudWatch log group for ECS Exec
- frontend target group ARN
- container images

## Why This Matches Pattern 5

- only the edge-facing `frontend` tier is load balanced
- the internal `api` tier is reached by Service Connect name `api`
- the `worker` tier remains private and does not expose an inbound endpoint

This keeps public ingress explicit and avoids creating extra internal ALBs just
to move traffic between private services.
