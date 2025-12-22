# AWS re:Invent 2025 - ECS Updates & Service Quotas Management

---

## Slide 1: AWS re:Invent 2025 - ECS Updates & Learnings

**Title Slide**

### Content:
- **Main Title:** AWS re:Invent Insights: ECS Service Connect & Service Quotas
- **Subtitle:** New Features, Deployment Strategies, and Quota Management
- **Presented by:** PrasanthDevops339
- **Date:** December 2025

### Talking Points:
- Welcome the team and set context about AWS re:Invent visit
- Two main topics covered:
  - Topic 1: ECS Service Connect and new deployment features (Slides 2-4)
  - Topic 2: Service Quotas management and automation (Slides 5-6)
  - Topic 3: Additional insights on API culture and Platform Engineering (Slide 7)
- These updates directly address challenges with ECS networking and quota limitations
- Focus on practical applications for current infrastructure

---

## Slide 2: ECS Networking Evolution - From awsvpc to Service Connect

### Visual Content:
**Comparison Table:**

| Traditional awsvpc Mode | Service Connect |
|------------------------|-----------------||
| ENI per task | Proxy-based communication |
| Manual service discovery | Automatic service discovery |
| Load balancer required | Built-in load balancing |
| Complex networking setup | Simplified configuration |

### Talking Points:

1. **awsvpc Networking Mode Context:**
   - Traditional ECS networking uses Elastic Network Interfaces (ENIs) per task
   - Each task gets its own private IP address within the VPC
   - Provides strong network isolation but adds complexity

2. **Challenges with Traditional Approach:**
   - Manual service discovery configuration required
   - Load balancer setup for each service
   - Complex security group management
   - ENI limits can become bottlenecks

3. **Service Connect Introduction:**
   - Built on AWS Cloud Map for automatic service discovery
   - Uses Envoy proxy sidecar for traffic management
   - Simplifies microservices communication within ECS clusters
   - No need for external load balancers for inter-service communication

4. **Key Benefit:**
   - Services communicate through proxies automatically
   - Reduces operational overhead and improves service-to-service reliability

**Reference:** https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-networking-awsvpc.html

---

## Slide 3: ECS Service Connect - Key Features & Benefits

### Visual Content:
**Feature Highlights:**
- ✅ Built-in Service Discovery
- ✅ Connection Pooling
- ✅ Client-side Load Balancing
- ✅ TLS Encryption Support
- ✅ Automatic Health Checks
- ✅ Traffic Metrics & Observability

### Talking Points:

1. **Automatic Service Discovery:**
   - Service Connect automatically registers services in AWS Cloud Map
   - No need to manually configure service endpoints
   - Services reference each other by friendly names (e.g., "orders-service")
   - DNS-based discovery happens automatically

2. **TLS Encryption Between Services:**
   - Service Connect now supports mutual TLS (mTLS) for service-to-service communication
   - Encrypts traffic between microservices without application changes
   - AWS manages certificate lifecycle automatically
   - Improves security posture for internal communications

3. **Enhanced Observability:**
   - Built-in CloudWatch metrics for connection success rates
   - Latency metrics per service endpoint
   - Active connection tracking
   - Better visibility into microservices health

4. **Connection Management:**
   - Connection pooling reduces overhead
   - Automatic retries with exponential backoff
   - Circuit breaking to prevent cascade failures
   - Significantly improves resilience

5. **Cost Optimization:**
   - Eliminates need for Application Load Balancers between internal services
   - Reduces data transfer costs
   - More efficient resource utilization

**References:**
- https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect.html
- https://catalog.workshops.aws/ecs-immersion-day/en-US/50-networking/ecs-service-connect-tls

---

## Slide 4: New ECS Deployment Features

### Visual Content:
**Deployment Types Comparison:**

| Deployment Type | Use Case | Key Feature |
|----------------|----------|-------------|
| Rolling Update | Standard deployments | Gradual replacement |
| Blue/Green | Zero-downtime critical apps | Complete environment swap |
| External | Custom CI/CD integration | Third-party orchestration |
| Circuit Breaker | Automatic rollback | Failure detection |

### Talking Points:

1. **Rolling Update Enhancements:**
   - Configure minimum healthy percent (default 100%)
   - Maximum percent controls how many tasks can run during deployment (default 200%)
   - Better control over deployment speed and resource usage
   - Can pause deployments for validation

2. **Blue/Green Deployments with CodeDeploy:**
   - Complete environment duplication
   - Traffic shifts incrementally (linear, canary, or all-at-once)
   - Built-in testing phase before full cutover
   - One-click rollback capability
   - Ideal for production-critical services

3. **Deployment Circuit Breaker (Game Changer):**
   - **What it solves:** Automatically detects failed deployments
   - **How it works:**
     - Monitors deployment health checks
     - If tasks repeatedly fail to start, triggers automatic rollback
     - Prevents bad deployments from taking down services
   - **Configuration:** Set failure thresholds (tasks failed, time window)
   - **Benefit:** Reduces MTTD (Mean Time To Detect) and MTTR (Mean Time To Recover)

4. **External Deployment Controller:**
   - Allows integration with Jenkins, GitLab CI, or custom tools
   - Full control over deployment orchestration
   - Useful for complex multi-region deployments
   - Can leverage for existing CI/CD pipelines

5. **Best Practice Recommendation:**
   - Use Circuit Breaker for all production services
   - Combine with CloudWatch alarms for comprehensive monitoring
   - Consider Blue/Green for customer-facing APIs

**References:**
- https://catalog.workshops.aws/ecs-immersion-day/en-US/80-deployments
- https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_service-options.html

---

## Slide 5: Service Quotas Challenge - Our Recent Experience

### Visual Content:
**Problem Statement:**
- "Recently hit service quota limits impacting deployments"
- Common quotas affected: ENIs per region, ECS tasks per service, CloudWatch log groups

**Impact Flow:**
```
Deployment Failed ❌
    ↓
Quota Limit Reached
    ↓
Manual Request Required
    ↓
2-3 Days Wait Time ⏰
```

### Talking Points:

1. **Our Recent Issue:**
   - Encountered quota limits during peak deployment periods
   - Specifically hit limits on ENI limits, ECS tasks per cluster, EC2 instance limits
   - Resulted in deployment failures and delays

2. **Traditional Quota Management Problems:**
   - Manual process to request quota increases through AWS Console
   - Required opening support tickets
   - 2-3 day turnaround time for approvals
   - Reactive rather than proactive approach
   - No visibility into quota usage across multiple accounts

3. **Why This Matters:**
   - As we scale microservices, we hit quotas more frequently
   - Impacts delivery timelines and SLAs
   - Creates operational toil for the team
   - Can cause production incidents if quotas reached during critical times

4. **The Need for Automation:**
   - Manual quota management doesn't scale with our growth
   - Need proactive monitoring and automatic adjustments
   - Should be part of our infrastructure as code approach

---

## Slide 6: Service Quotas Automation - The Solution

### Visual Content:
**Automation Flow:**
```
CloudWatch Alarm (80% quota usage)
    ↓
Automatic Quota Increase Request
    ↓
Service Quotas Template Applied
    ↓
All Accounts Updated
```

**Key Features:**
- 🔄 Automatic Quota Management
- 📊 Organization-wide Templates
- ⚡ Proactive Monitoring
- 🏢 Multi-account Support

### Talking Points:

1. **Automatic Quota Management:**
   - AWS provides automatic quota increase requests via API
   - Can be triggered programmatically based on usage thresholds
   - Integrate with CloudWatch alarms to monitor quota consumption
   - **Example workflow:**
     - Set CloudWatch alarm at 80% of quota usage
     - Alarm triggers Lambda function
     - Lambda calls Service Quotas API to request increase
     - Automatic approval for many service quotas

2. **Service Quotas Organization Templates:**
   - Define quota baselines across all AWS accounts in your organization
   - Template specifies desired quota values for services
   - **Benefits:**
     - New accounts automatically get appropriate quotas
     - Consistent quota settings across environments
     - Reduces account setup time
     - Prevents quota issues before they happen

3. **Implementation Approach:**
   - **Phase 1:** Audit current quota usage across all accounts
   - **Phase 2:** Create organization template with increased defaults
   - **Phase 3:** Set up CloudWatch monitoring and alerts
   - **Phase 4:** Automate quota increase requests via Lambda
   - **Phase 5:** Regular review and adjustment of templates

4. **Specific Services to Monitor:**
   - ECS: Tasks per service, services per cluster
   - VPC: ENIs per region, VPCs per region
   - EC2: Instance limits per type
   - CloudWatch: Log groups, metrics
   - Service Connect specific quotas

5. **Metrics to Track:**
   - Quota utilization percentage per service
   - Rate of quota consumption (trending)
   - Quota increase request success rate
   - Time to quota increase approval

6. **Recommended Actions:**
   - Implement quota monitoring dashboard
   - Create Terraform/CloudFormation for quota templates
   - Document quota requirements per service
   - Establish quota review in architecture discussions
   - Set up alerting for quota breaches

7. **Expected Outcomes:**
   - Eliminate deployment failures due to quota limits
   - Reduce operational overhead
   - Proactive rather than reactive quota management
   - Better capacity planning

**References:**
- https://docs.aws.amazon.com/servicequotas/latest/userguide/automatic-management.html
- https://docs.aws.amazon.com/servicequotas/latest/userguide/organization-templates.html

---

## Slide 7: Additional AWS Insights - Culture & Platform Engineering

### Section 1: APIs as a Promise - AWS Culture

**Quote Box:**
> "Once a team delivers an API, it's a promise that it will always be available. Any changes must not break the API contract."
> — AWS API Culture

### Talking Points:

1. **The API Contract Mindset:**
   - At AWS, once a team releases an API, it becomes an unbreakable promise
   - This is a cultural principle embedded in how Amazon builds services
   - The moment you expose an API, you commit to backward compatibility and availability

2. **What This Means in Practice:**
   - **No Breaking Changes:** Teams cannot remove or change API endpoints without extensive deprecation periods
   - **Version Management:** New features must be additive, not destructive
   - **Availability SLA:** The API must maintain agreed-upon uptime (typically 99.9%+)
   - **Performance Guarantees:** Response times and throughput must meet commitments

3. **Real-World Example:**
   - AWS maintains APIs from services launched 15+ years ago (S3, EC2)
   - Customers rely on API stability for mission-critical workloads
   - Even internal service-to-service APIs follow this principle

4. **How This Applies to Our Team:**
   - **Design APIs carefully:** Once released, we're committed long-term
   - **Use versioning:** Implement API versioning from day one (v1, v2, etc.)
   - **Deprecation process:**
     - Announce deprecation at least 6-12 months in advance
     - Support both old and new versions during transition
     - Provide migration guides and tools
     - Never just "turn off" an API
   - **Testing rigor:** Comprehensive contract testing to prevent accidental breaking changes
   - **Monitoring:** Track API usage to understand impact before changes

5. **Benefits of This Approach:**
   - Builds trust with internal and external consumers
   - Reduces coordination overhead (teams can rely on stable interfaces)
   - Encourages thoughtful API design upfront
   - Forces long-term thinking about architecture decisions

6. **Action Items:**
   - Implement OpenAPI/Swagger specifications for all APIs
   - Set up contract testing in CI/CD pipelines
   - Create API deprecation policy document
   - Review existing APIs for breaking change risks

---

### Section 2: Platform Engineering That Actually Works

**Session:** SEC206 - "Rethinking DevSecOps with Platform Engineering That Actually Works"
**Presenters:** Danny Cortegaca (Principal Security Specialist), Cameron Smith (Sr. Security Specialist)

### Talking Points:

1. **What is Platform Engineering?**
   - Platform teams build internal tools and services that enable product teams to move faster
   - Shift from "DevOps as a practice" to "DevOps as a platform"
   - Goal: Reduce cognitive load on application developers
   - Provide self-service capabilities with security guardrails built-in

2. **The Security Capabilities Adoption Framework:**

   **Step 1: Select a Tool**
   - Platform team evaluates security tools (SAST, DAST, container scanning, etc.)
   - Consider ease of use, integration capabilities, and developer experience
   - Pick what developers will actually use, not just the most comprehensive

   **Step 2: Create a Template**
   - Build infrastructure-as-code templates with security baked in
   - Examples: CloudFormation/Terraform with GuardDuty, Security Hub, Config Rules
   - Pre-configured CI/CD pipelines with security scanning stages
   - Make secure patterns the default and easiest path

   **Step 3: Distribute**
   - Distribution is where platform teams often fail
   - Two paths: immediate adoption or iterate based on feedback

   **Step 4: Gather & Incorporate Feedback**
   - Continuous feedback loop with product teams
   - What's working? What's blocking productivity?
   - Measure adoption rates and friction points
   - Iterate on templates based on real-world usage

   **Step 5: Run & Maintain**
   - Platform team maintains the tools and templates
   - Keep dependencies updated
   - Provide support and documentation
   - Monitor for new security threats and update tooling

3. **Key Takeaways:**

   **a) Developer Experience is Critical:**
   - Security tools fail when they're too complex or slow down developers
   - Platform teams must obsess over usability
   - "Shift left" only works if tools are frictionless

   **b) Golden Paths, Not Gates:**
   - Provide "golden path" templates that are pre-approved and easy to use
   - Don't block developers with approval processes
   - Guide toward secure patterns by making them the default

   **c) Self-Service with Guardrails:**
   - Developers should provision infrastructure themselves
   - With security controls built-in (encryption by default, least privilege IAM)
   - Platform provides the "paved road"—safe, fast, and well-maintained

   **d) Measure Adoption, Not Compliance:**
   - Traditional metric: "Are we compliant with policy X?"
   - Platform engineering metric: "How many teams chose to use our secure template?"
   - If adoption is low, the platform failed—not the developers

4. **How This Relates to Our Platform Team:**
   - We are building an internal platform for application teams
   - Our ECS templates, CI/CD pipelines, and infrastructure modules are "platform products"
   - We need to think like product managers, not just operators

5. **Applying This Framework:**

   **Example: ECS Service Deployment**
   - **Select:** ECS Service Connect
   - **Template:** Create Terraform module with Service Connect pre-configured
   - **Distribute:** Make available in internal module registry
   - **Gather Feedback:** Survey teams—is it easy to use? What's missing?
   - **Incorporate:** Add logging, monitoring dashboards, example apps
   - **Run & Maintain:** Platform team supports the module, handles updates

   **Example: Security Scanning**
   - **Select:** Container scanning tool (Amazon ECR image scanning)
   - **Template:** CI/CD pipeline template with automated scanning
   - **Distribute:** Push to all repos with migration guide
   - **Gather Feedback:** Are scans too slow? Too many false positives?
   - **Incorporate:** Tune scanning rules, add policy exceptions workflow
   - **Run & Maintain:** Platform team manages scanner updates

6. **Cultural Shift Required:**
   - Platform team success = Product team velocity + security
   - Measure:
     - Time to provision new service (should decrease)
     - Security incidents (should decrease)
     - Developer satisfaction (survey quarterly)
     - Adoption rate of platform tools
   - If teams are working around our tools, we need to improve them

7. **Recommendations:**

   **Immediate:**
   - Create feedback channel (Slack, office hours, surveys)
   - Document "golden path" for common tasks
   - Measure baseline: How long does it take to deploy a new service?

   **Short-term (1-3 months):**
   - Build self-service portal or CLI for common platform operations
   - Create example repositories demonstrating best practices
   - Implement the Service Connect template

   **Long-term (3-6 months):**
   - Establish Platform Team product roadmap based on feedback
   - Create internal platform documentation site
   - Build custom tooling to bridge gaps in AWS services
   - Adopt quota management automation

8. **Success Metrics:**
   - **Adoption Rate:** % of teams using platform templates vs. custom solutions
   - **Time to Production:** How quickly can a team go from idea to deployed service?
   - **Security Posture:** Reduction in security findings, compliance violations
   - **Developer Satisfaction:** NPS score from internal teams
   - **Ticket Volume:** Reduced support requests as self-service improves
   - **Deployment Frequency:** Teams should deploy more often with better tooling

---

### Final Thoughts:

**Connect Both Topics:**
- Both "API as a Promise" and "Platform Engineering" share a common theme: **reliability and trust**
- When we build APIs or platform tools, we're making commitments to our users
- We must be as reliable and backward-compatible as AWS's public services
- Platform engineering is about making the secure, scalable, reliable path the easy path

**Call to Action:**
- Adopt the API promise mindset for our internal services
- Evolve from "DevOps team" to "Platform team"
- Measure success by how much we enable other teams, not just by what we build

---

## Slide 8: Next Steps & Action Items

### Immediate Actions (Week 1-2):

1. **ECS Service Connect:**
   - Proof of concept on non-production service
   - Document findings and benefits

2. **Deployment Circuit Breaker:**
   - Enable on all production ECS services
   - Configure appropriate failure thresholds

3. **Service Quotas Audit:**
   - Review current quota usage across all accounts
   - Identify services approaching limits

### Short-term (Month 1-2):

1. **Service Connect Rollout:**
   - Create Terraform modules with Service Connect
   - Migrate internal services from ALB to Service Connect

2. **Quota Automation:**
   - Implement CloudWatch alarms for quota monitoring
   - Create Lambda functions for automatic quota requests
   - Build organization-wide quota templates

3. **Platform Engineering:**
   - Establish feedback channels with application teams
   - Document golden paths for common tasks
   - Create example repositories

### Long-term (Quarter 1-2):

1. **Full Platform Adoption:**
   - Self-service portal for infrastructure provisioning
   - Internal documentation site
   - Regular platform team roadmap reviews

2. **API Governance:**
   - Implement API versioning standards
   - Contract testing in all CI/CD pipelines
   - API deprecation policy

3. **Continuous Improvement:**
   - Quarterly developer satisfaction surveys
   - Platform metrics dashboard
   - Regular review of quota templates and automation

---

## Questions & Discussion

**Thank you for attending!**

### Resources:
- ECS Workshop: https://catalog.workshops.aws/ecs-immersion-day/en-US
- Service Connect Documentation: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect.html
- Service Quotas: https://docs.aws.amazon.com/servicequotas/latest/userguide/

### Contact:
- For questions or feedback, reach out to the Platform Team
- Let's schedule follow-up sessions to discuss implementation details

---

## Converting This Markdown to PowerPoint

### Using Pandoc:
```bash
pandoc aws-reinvent-presentation.md -o aws-reinvent-presentation.pptx -t pptx
```

### Using Marp:
```bash
marp aws-reinvent-presentation.md --pptx -o aws-reinvent-presentation.pptx
```

### Customization Tips:
- Add your company logo and branding
- Include the architecture diagrams from the images
- Adjust colors to match your presentation theme
- Add speaker notes for detailed talking points
- Include screenshots from AWS Console where relevant