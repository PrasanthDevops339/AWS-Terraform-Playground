# 2.0 — Feature #2 Extended Requirements: Design Memo

**Author:** Cloud Platform Engineering
**Status:** Draft for Sprint 5/6 design review
**Scope:** Two extensions to the AMI Lifecycle Management feature
**Related:** `CITP-30 — Establish AMI Lifecycle Strategy Design Draft`, Feature #2 acceptance criteria

---

## 1. Executive Summary

Two new requirements have surfaced that affect the AMI consumption model. Both are solvable with native AWS primitives we already plan to use (Image Builder, SSM Parameter Store, EventBridge, ASG Instance Refresh) — no new platform service required. The patterns below extend the existing strategy doc rather than replacing it.

| # | Requirement | Recommended Pattern | Effort |
|---|---|---|---|
| 1 | Same AMI consumed across dev → pre-prod → prod, without manual pinning | Per-environment SSM Parameter Store pointers with a **promotion pipeline**. Each env reads `/prasan-ins/ami/<app>/<env>/current`. Dev's value is *copied forward* to higher envs after validation, never resolved at higher-env Terraform plan time. | M |
| 2 | Patch the AMI in an ASG without Terraform drift and without app team deploys | Use `image_id = "resolve:ssm:<param>"` in the launch template (resolved at instance launch, not plan time) plus an **EventBridge → Lambda → StartInstanceRefresh** flow triggered by SSM parameter changes. Terraform sees no drift; app teams don't deploy. | M |

Both patterns coexist with your existing decisions on lifecycle policies, exemption tags, and the SSM patch-in-place compensating control. Critically, **Pattern #2 changes one rule in Appendix B of your draft doc** ("Use a concrete AMI ID; no dynamic references at runtime") — we need to consciously decide whether to evolve that rule or keep it and accept a different trade-off. Section 6 covers that decision.

---

## 2. Why These Are Hard (and Why We Care)

A quick reframing for the design review:

- **Today's behavior**: app teams' Terraform pulls `data.aws_ami.latest`. Platform publishes weekly. Result: dev deploy on Day 1 ≠ pre-prod deploy on Day 30. **You're effectively shipping different artifacts through your SDLC**, which breaks the basic immutability promise of AMI rotation.
- **Today's patching pain**: rotating AMIs requires a launch template update, which lives in app team Terraform, which means platform-driven security patching becomes app-team-driven deployments. **Patch velocity becomes a function of app team release calendars**, which is the opposite of what an immutable model is supposed to enable.

Both problems share the same root cause: **the launch template's `image_id` is bound to the same Terraform run that owns the rest of the workload's infrastructure**. The fix is to break that coupling — but cleanly, with governance still intact.

---

## 3. Requirement #1 — Environment-Locked AMI Promotion

### 3.1 Goal

> When an app team deploys AMI `ami-x` in dev, the *same* `ami-x` should be what they get in pre-prod and prod, even if those deployments are weeks apart — **without** asking app teams to manually pin AMI IDs in their Terraform.

Restated as a design constraint: app teams keep using a "latest" semantic in their code, but the *meaning of "latest" varies by environment* and is controlled by platform-driven promotion.

### 3.2 Recommended Pattern: Per-Environment SSM Parameter Store Pointers + Promotion Pipeline

Three moving parts:

1. **Image Builder** publishes a new AMI weekly (existing behavior). Distribution config writes the AMI ID to `/prasan-ins/ami/<os-family>/dev/current` in each consuming account. Image Builder has [native SSM Parameter Store integration in distribution configs](https://docs.aws.amazon.com/imagebuilder/latest/userguide/cr-upd-ami-distribution-settings.html) — no Lambda glue needed for the dev pointer.
2. **Promotion pipeline** (GitLab) is triggered after dev validation succeeds. It reads `/prasan-ins/ami/<app>/dev/current` and writes that value to `/prasan-ins/ami/<app>/preprod/current`. Same pattern preprod → prod. The promotion pipeline is the *only* writer of preprod and prod parameters.
3. **App team Terraform** uses a `data "aws_ssm_parameter"` lookup against `/prasan-ins/ami/<app>/${var.environment}/current`. They never see an AMI ID in code. They never pin manually.

The key insight: **dev gets the "weekly latest"; preprod and prod get the "latest dev value at the moment of promotion."** The promotion freezes the value forward.

### 3.3 HLD — Requirement #1

```xml
<mxGraphModel dx="1422" dy="762" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1400" pageHeight="900" math="0" shadow="0">
  <root>
    <mxCell id="0" />
    <mxCell id="1" parent="0" />

    <!-- Title -->
    <mxCell id="title" value="HLD — Requirement #1: Per-Environment AMI Promotion (prasan- 2.0)" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=16;fontStyle=1;" vertex="1" parent="1">
      <mxGeometry x="350" y="20" width="700" height="30" as="geometry" />
    </mxCell>

    <!-- Central Operations Account -->
    <mxCell id="ops_acct" value="AWS Account — prasan-ins-operations-prd (Central)" style="points=[[0,0],[0.25,0],[0.5,0],[0.75,0],[1,0],[1,0.25],[1,0.5],[1,0.75],[1,1],[0.75,1],[0.5,1],[0.25,1],[0,1],[0,0.75],[0,0.5],[0,0.25]];shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_account;verticalLabelPosition=top;verticalAlign=bottom;fillColor=#F5F5F5;strokeColor=#666666;fontStyle=1;fontSize=11;" vertex="1" parent="1">
      <mxGeometry x="60" y="80" width="380" height="800" as="geometry" />
    </mxCell>

    <mxCell id="img_builder" value="EC2 Image Builder&#10;(weekly pipeline)" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=11;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.image_builder;" vertex="1" parent="ops_acct">
      <mxGeometry x="50" y="80" width="60" height="60" as="geometry" />
    </mxCell>

    <mxCell id="dist_cfg" value="Distribution Config&#10;(ssmParameterConfigurations)" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=10;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.image_builder;" vertex="1" parent="ops_acct">
      <mxGeometry x="200" y="80" width="60" height="60" as="geometry" />
    </mxCell>

    <mxCell id="lifecycle_pol" value="Image Builder&#10;Lifecycle Policy&#10;(60d deprecate / 75d disable)" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=10;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.image_builder;" vertex="1" parent="ops_acct">
      <mxGeometry x="50" y="220" width="60" height="60" as="geometry" />
    </mxCell>

    <mxCell id="ami_central" value="Golden AMIs&#10;(shared cross-account)" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=10;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.ec2_ami;" vertex="1" parent="ops_acct">
      <mxGeometry x="200" y="220" width="60" height="60" as="geometry" />
    </mxCell>

    <mxCell id="promo_pipeline" value="GitLab&#10;Promotion Pipeline&#10;(dev→preprod→prod)" style="outlineConnect=0;fontColor=#FFFFFF;gradientColor=none;strokeColor=none;fillColor=#FC6D26;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=10;fontStyle=1;rounded=1;" vertex="1" parent="ops_acct">
      <mxGeometry x="125" y="380" width="120" height="60" as="geometry" />
    </mxCell>

    <mxCell id="ssm_central" value="SSM Param (audit)&#10;/prasan-ins/ami/&lt;app&gt;/promotions" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=10;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.systems_manager_parameter_store;" vertex="1" parent="ops_acct">
      <mxGeometry x="125" y="500" width="60" height="60" as="geometry" />
    </mxCell>

    <!-- Dev Account -->
    <mxCell id="dev_acct" value="AWS Account — Dev" style="points=[[0,0],[0.25,0],[0.5,0],[0.75,0],[1,0],[1,0.25],[1,0.5],[1,0.75],[1,1],[0.75,1],[0.5,1],[0.25,1],[0,1],[0,0.75],[0,0.5],[0,0.25]];shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_account;verticalLabelPosition=top;verticalAlign=bottom;fillColor=#E3F2FD;strokeColor=#1976D2;fontStyle=1;fontSize=11;" vertex="1" parent="1">
      <mxGeometry x="500" y="80" width="280" height="240" as="geometry" />
    </mxCell>

    <mxCell id="dev_ssm" value="SSM Param&#10;/prasan-ins/ami/myapp/dev/current&#10;= ami-WEEKLY-LATEST" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=9;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.systems_manager_parameter_store;" vertex="1" parent="dev_acct">
      <mxGeometry x="30" y="60" width="60" height="60" as="geometry" />
    </mxCell>

    <mxCell id="dev_tf" value="App Team Terraform&#10;data.aws_ssm_parameter&#10;(reads /dev/current)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#7B42BC;strokeColor=#5C2EAA;fontColor=#FFFFFF;fontSize=10;fontStyle=1;" vertex="1" parent="dev_acct">
      <mxGeometry x="140" y="55" width="120" height="70" as="geometry" />
    </mxCell>

    <mxCell id="dev_asg" value="Dev ASG&#10;(rolling refresh)" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=10;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.auto_scaling2;" vertex="1" parent="dev_acct">
      <mxGeometry x="105" y="160" width="60" height="60" as="geometry" />
    </mxCell>

    <!-- PreProd Account -->
    <mxCell id="pp_acct" value="AWS Account — Pre-Prod" style="points=[[0,0],[0.25,0],[0.5,0],[0.75,0],[1,0],[1,0.25],[1,0.5],[1,0.75],[1,1],[0.75,1],[0.5,1],[0.25,1],[0,1],[0,0.75],[0,0.5],[0,0.25]];shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_account;verticalLabelPosition=top;verticalAlign=bottom;fillColor=#FFF3E0;strokeColor=#F57C00;fontStyle=1;fontSize=11;" vertex="1" parent="1">
      <mxGeometry x="500" y="360" width="280" height="240" as="geometry" />
    </mxCell>

    <mxCell id="pp_ssm" value="SSM Param&#10;/prasan-ins/ami/myapp/preprod/current&#10;= ami-PROMOTED-FROM-DEV" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=9;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.systems_manager_parameter_store;" vertex="1" parent="pp_acct">
      <mxGeometry x="30" y="60" width="60" height="60" as="geometry" />
    </mxCell>

    <mxCell id="pp_tf" value="App Team Terraform&#10;data.aws_ssm_parameter&#10;(reads /preprod/current)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#7B42BC;strokeColor=#5C2EAA;fontColor=#FFFFFF;fontSize=10;fontStyle=1;" vertex="1" parent="pp_acct">
      <mxGeometry x="140" y="55" width="120" height="70" as="geometry" />
    </mxCell>

    <mxCell id="pp_asg" value="Pre-Prod ASG" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=10;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.auto_scaling2;" vertex="1" parent="pp_acct">
      <mxGeometry x="105" y="160" width="60" height="60" as="geometry" />
    </mxCell>

    <!-- Prod Account -->
    <mxCell id="prod_acct" value="AWS Account — Prod" style="points=[[0,0],[0.25,0],[0.5,0],[0.75,0],[1,0],[1,0.25],[1,0.5],[1,0.75],[1,1],[0.75,1],[0.5,1],[0.25,1],[0,1],[0,0.75],[0,0.5],[0,0.25]];shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_account;verticalLabelPosition=top;verticalAlign=bottom;fillColor=#FFEBEE;strokeColor=#C62828;fontStyle=1;fontSize=11;" vertex="1" parent="1">
      <mxGeometry x="500" y="640" width="280" height="240" as="geometry" />
    </mxCell>

    <mxCell id="prod_ssm" value="SSM Param&#10;/prasan-ins/ami/myapp/prod/current&#10;= ami-PROMOTED-FROM-PREPROD" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=9;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.systems_manager_parameter_store;" vertex="1" parent="prod_acct">
      <mxGeometry x="30" y="60" width="60" height="60" as="geometry" />
    </mxCell>

    <mxCell id="prod_tf" value="App Team Terraform&#10;data.aws_ssm_parameter&#10;(reads /prod/current)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#7B42BC;strokeColor=#5C2EAA;fontColor=#FFFFFF;fontSize=10;fontStyle=1;" vertex="1" parent="prod_acct">
      <mxGeometry x="140" y="55" width="120" height="70" as="geometry" />
    </mxCell>

    <mxCell id="prod_asg" value="Prod ASG" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=10;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.auto_scaling2;" vertex="1" parent="prod_acct">
      <mxGeometry x="105" y="160" width="60" height="60" as="geometry" />
    </mxCell>

    <!-- Validation Pipeline -->
    <mxCell id="val_pipe" value="Dev Validation&#10;Pipeline" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FC6D26;strokeColor=#A8390C;fontColor=#FFFFFF;fontSize=10;fontStyle=1;" vertex="1" parent="1">
      <mxGeometry x="900" y="170" width="120" height="50" as="geometry" />
    </mxCell>

    <mxCell id="val_pipe2" value="Pre-Prod Validation&#10;Pipeline (smoke + integ)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FC6D26;strokeColor=#A8390C;fontColor=#FFFFFF;fontSize=10;fontStyle=1;" vertex="1" parent="1">
      <mxGeometry x="900" y="450" width="120" height="50" as="geometry" />
    </mxCell>

    <mxCell id="approval" value="Change Approval&#10;Gate (manual)" style="rhombus;whiteSpace=wrap;html=1;fillColor=#FFE6CC;strokeColor=#D79B00;fontSize=10;fontStyle=1;" vertex="1" parent="1">
      <mxGeometry x="900" y="730" width="120" height="60" as="geometry" />
    </mxCell>

    <!-- Edges -->
    <mxCell id="e1" value="builds" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="img_builder" target="ami_central" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="e2" value="distributes&#10;+ writes SSM" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="dist_cfg" target="dev_ssm" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="e3" value="manages" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;dashed=1;fontSize=9;" edge="1" source="lifecycle_pol" target="ami_central" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="e4" value="reads" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="dev_tf" target="dev_ssm" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="e5" value="updates LT" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="dev_tf" target="dev_asg" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="e6" value="reads" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="pp_tf" target="pp_ssm" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="e7" value="updates LT" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="pp_tf" target="pp_asg" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="e8" value="reads" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="prod_tf" target="prod_ssm" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="e9" value="updates LT" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="prod_tf" target="prod_asg" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="e10" value="signals success" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;dashed=1;fontSize=9;" edge="1" source="dev_asg" target="val_pipe" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="e11" value="triggers" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="val_pipe" target="promo_pipeline" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="e12" value="copies dev→preprod" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;strokeColor=#FC6D26;fontSize=9;fontStyle=1;" edge="1" source="promo_pipeline" target="pp_ssm" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="e13" value="signals success" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;dashed=1;fontSize=9;" edge="1" source="pp_asg" target="val_pipe2" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="e14" value="triggers" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="val_pipe2" target="approval" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="e15" value="copies preprod→prod" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;strokeColor=#FC6D26;fontSize=9;fontStyle=1;" edge="1" source="approval" target="prod_ssm" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="e16" value="audit log" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;dashed=1;fontSize=9;" edge="1" source="promo_pipeline" target="ssm_central" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

  </root>
</mxGraphModel>
```

> **Import:** open [app.diagrams.net](https://app.diagrams.net) → **Extras → Edit Diagram** → paste → **OK**.

### 3.4 LLD — Requirement #1 (Parameter Naming, IAM, Cross-Account)

```xml
<mxGraphModel dx="1422" dy="762" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1500" pageHeight="900" math="0" shadow="0">
  <root>
    <mxCell id="0" />
    <mxCell id="1" parent="0" />

    <mxCell id="title" value="LLD — Requirement #1: SSM Promotion (Parameter Schema, IAM, Promotion Logic)" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=15;fontStyle=1;" vertex="1" parent="1">
      <mxGeometry x="350" y="20" width="800" height="30" as="geometry" />
    </mxCell>

    <!-- SSM Parameter Schema Box -->
    <mxCell id="schema_box" value="Parameter Schema (per consuming account)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFF2CC;strokeColor=#D6B656;fontSize=11;fontStyle=1;verticalAlign=top;" vertex="1" parent="1">
      <mxGeometry x="60" y="80" width="430" height="280" as="geometry" />
    </mxCell>

    <mxCell id="schema_text" value="/prasan-ins/ami/&lt;app&gt;/&lt;env&gt;/current        ← active AMI&#10;/prasan-ins/ami/&lt;app&gt;/&lt;env&gt;/previous       ← LKG (auto-rollback)&#10;/prasan-ins/ami/&lt;app&gt;/&lt;env&gt;/promoted_at    ← ISO timestamp&#10;/prasan-ins/ami/&lt;app&gt;/&lt;env&gt;/promoted_from   ← source env + run_id&#10;&#10;DataType: aws:ec2:image (validates AMI ID format)&#10;Tier: Standard (free) or Advanced (if &gt;4KB metadata)&#10;KMS: alias/prasan-ins-ssm-cmk (CMK per account)&#10;Tags:&#10;  ManagedBy=AmiLifecyclePlatform&#10;  app=&lt;name&gt;  env=dev|preprod|prod&#10;  ami-lifecycle-exempt=false (default)" style="text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=top;whiteSpace=wrap;rounded=0;fontSize=11;fontFamily=Courier New;" vertex="1" parent="1">
      <mxGeometry x="80" y="115" width="400" height="240" as="geometry" />
    </mxCell>

    <!-- IAM Roles Box -->
    <mxCell id="iam_box" value="IAM Roles &amp; Trust Boundaries" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#DAE8FC;strokeColor=#6C8EBF;fontSize=11;fontStyle=1;verticalAlign=top;" vertex="1" parent="1">
      <mxGeometry x="540" y="80" width="430" height="280" as="geometry" />
    </mxCell>

    <mxCell id="iam_text" value="ImageBuilderDistributionRole (central)&#10;  ssm:PutParameter ON /prasan-ins/ami/*/dev/current&#10;  ec2:DescribeImages, ec2:CopyImage, ec2:ModifyImageAttribute&#10;  Cross-acct: assume Ec2ImageBuilderDistributionCrossAccountRole&#10;&#10;PromotionPipelineRole (central, GitLab-assumed)&#10;  ssm:GetParameter ON dev/current&#10;  ssm:PutParameter ON preprod/current, prod/current&#10;  CloudWatch:PutLogEvents (audit)&#10;&#10;AppTeamTerraformRole (per workload account)&#10;  ssm:GetParameter ON /prasan-ins/ami/&lt;THEIR-APP&gt;/${env}/current&#10;  NO PutParameter (read-only on AMI pointers)&#10;&#10;SCP guardrail (org-wide):&#10;  Deny ssm:PutParameter on /prasan-ins/ami/*/preprod/*&#10;        and /prasan-ins/ami/*/prod/*&#10;        UNLESS principal = PromotionPipelineRole" style="text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=top;whiteSpace=wrap;rounded=0;fontSize=10;fontFamily=Courier New;" vertex="1" parent="1">
      <mxGeometry x="555" y="115" width="415" height="240" as="geometry" />
    </mxCell>

    <!-- Promotion Pipeline Logic -->
    <mxCell id="promo_box" value="Promotion Pipeline Logic (GitLab CI)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFE6CC;strokeColor=#D79B00;fontSize=11;fontStyle=1;verticalAlign=top;" vertex="1" parent="1">
      <mxGeometry x="60" y="400" width="910" height="280" as="geometry" />
    </mxCell>

    <mxCell id="promo_text" value="stages: [validate-source, promote, validate-target, notify]&#10;&#10;promote-dev-to-preprod:&#10;  rules:&#10;    - if: $CI_PIPELINE_SOURCE == &quot;trigger&quot; &amp;&amp; $TARGET_ENV == &quot;preprod&quot;&#10;  script:&#10;    - SOURCE_AMI=$(aws ssm get-parameter --name /prasan-ins/ami/${APP}/dev/current --query Parameter.Value --output text --region $REGION --profile dev)&#10;    - aws ec2 describe-images --image-ids $SOURCE_AMI --owners self  # confirms still active, not deprecated/disabled&#10;    - PREVIOUS=$(aws ssm get-parameter --name /prasan-ins/ami/${APP}/preprod/current --query Parameter.Value --output text --region $REGION --profile preprod || echo &quot;none&quot;)&#10;    - aws ssm put-parameter --name /prasan-ins/ami/${APP}/preprod/previous --value &quot;$PREVIOUS&quot; --type String --data-type aws:ec2:image --overwrite --profile preprod   # LKG snapshot&#10;    - aws ssm put-parameter --name /prasan-ins/ami/${APP}/preprod/current  --value &quot;$SOURCE_AMI&quot; --type String --data-type aws:ec2:image --overwrite --profile preprod&#10;    - aws ssm put-parameter --name /prasan-ins/ami/${APP}/preprod/promoted_from --value &quot;dev:${CI_PIPELINE_ID}&quot; --type String --overwrite --profile preprod&#10;    - aws ssm put-parameter --name /prasan-ins/ami/${APP}/preprod/promoted_at   --value &quot;$(date -Iseconds)&quot; --type String --overwrite --profile preprod&#10;    # IMPORTANT: this only updates the pointer. ASG refresh is triggered separately (see Req #2)." style="text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=top;whiteSpace=wrap;rounded=0;fontSize=9;fontFamily=Courier New;" vertex="1" parent="1">
      <mxGeometry x="75" y="430" width="880" height="240" as="geometry" />
    </mxCell>

    <!-- Cross-account flow -->
    <mxCell id="cross_box" value="Cross-Account Parameter Distribution (Image Builder native)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#D5E8D4;strokeColor=#82B366;fontSize=11;fontStyle=1;verticalAlign=top;" vertex="1" parent="1">
      <mxGeometry x="60" y="710" width="910" height="160" as="geometry" />
    </mxCell>

    <mxCell id="cross_text" value="distribution-configuration.json (used by Image Builder pipeline):&#10;{&#10;  &quot;distributions&quot;: [&#10;    {&#10;      &quot;region&quot;: &quot;us-east-1&quot;,&#10;      &quot;amiDistributionConfiguration&quot;: { &quot;name&quot;: &quot;prasan-ins-{{ imagebuilder:buildVersion }}&quot;, &quot;targetAccountIds&quot;: [&quot;DEV_ACCT&quot;, &quot;PREPROD_ACCT&quot;, &quot;PROD_ACCT&quot;] },&#10;      &quot;ssmParameterConfigurations&quot;: [&#10;        { &quot;amiAccountId&quot;: &quot;DEV_ACCT&quot;,     &quot;parameterName&quot;: &quot;/prasan-ins/ami/${APP}/dev/current&quot;, &quot;dataType&quot;: &quot;aws:ec2:image&quot; }&#10;        // NOTE: do NOT include preprod/prod here — those are ONLY written by promotion pipeline&#10;      ]&#10;    }&#10;  ]&#10;}" style="text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=top;whiteSpace=wrap;rounded=0;fontSize=10;fontFamily=Courier New;" vertex="1" parent="1">
      <mxGeometry x="75" y="740" width="880" height="120" as="geometry" />
    </mxCell>

  </root>
</mxGraphModel>
```

### 3.5 Terraform pattern (app team module)

```hcl
# modules/asg-workload/main.tf
# This is what app teams instantiate. Platform owns this module.

variable "app_name"     { type = string }
variable "environment"  {
  type = string
  validation {
    condition     = contains(["dev", "preprod", "prod"], var.environment)
    error_message = "environment must be dev, preprod, or prod"
  }
}

# Read the platform-managed pointer for this env
data "aws_ssm_parameter" "ami_current" {
  name = "/prasan-ins/ami/${var.app_name}/${var.environment}/current"
}

# Optional: read LKG for explicit rollback override
data "aws_ssm_parameter" "ami_previous" {
  name             = "/prasan-ins/ami/${var.app_name}/${var.environment}/previous"
  with_decryption  = true
  # tolerate missing on first run
}

resource "aws_launch_template" "this" {
  name_prefix   = "${var.app_name}-${var.environment}-"
  image_id      = data.aws_ssm_parameter.ami_current.value
  instance_type = var.instance_type
  # ... user_data, IAM, SGs etc.

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "this" {
  name = "${var.app_name}-${var.environment}"
  # explicit version, never $Latest/$Default (per existing strategy doc Appendix B)
  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      auto_rollback          = true
      alarm_specification {
        alarms = [aws_cloudwatch_metric_alarm.deployment_health.arn]
      }
    }
    triggers = ["launch_template"]
  }
  # ... min/max/desired, target groups, etc.
}
```

App teams write `terraform apply` once per env. The first apply populates the LT with the env-specific AMI. Subsequent platform-driven AMI pointer updates do **not** flow through this Terraform — that's where Requirement #2 comes in.

### 3.6 Limitations & Trade-offs (Requirement #1)

| # | Limitation | Mitigation |
|---|---|---|
| L1 | **Cold-start gap**: a brand-new app has no `dev/current` parameter on Day 0. App team's `terraform plan` errors. | Bootstrap step in onboarding runbook: platform pre-seeds `/prasan-ins/ami/<app>/dev/current` with the latest published AMI before app team's first apply. Or default to a public SSM parameter (`/aws/service/ami-amazon-linux-latest/...`) for the first run. |
| L2 | **Stale promotions**: if validation fails mid-pipeline, preprod/prod can drift behind dev for an unbounded time. | CloudWatch alarm on `(now - promoted_at) > 14 days` per env, surfaces aging promotions in a dashboard. Promotion pipeline emits SNS on every promote/skip event. |
| L3 | **`data.aws_ssm_parameter` resolves at plan time** — so re-running TF after platform pushes a new dev pointer *will* show drift in dev (not preprod/prod). | Two options: (a) accept that re-applying dev TF picks up the new pointer (consistent with "dev pulls latest" intent); or (b) use `resolve:ssm:` directly in the LT (Requirement #2 pattern) to make this drift-free in dev too. Recommended: pair this design with Req #2 so all envs are drift-free. |
| L4 | **AMI deprecation/disablement** in central account can land on a still-promoted AMI in prod. The 60d/75d Image Builder lifecycle clock is global; promotion delays mean a prod-pinned AMI may already be approaching disablement. | Two compensating controls: **(a)** promotion pipeline checks `aws ec2 describe-images` and refuses to promote AMIs already in `Deprecated` or `Disabled` state; **(b)** any AMI referenced by a `*/preprod/current` or `*/prod/current` SSM pointer gets the `ami-lifecycle-exempt-pointer=true` tag automatically (a daily Lambda reconciles), which the Image Builder lifecycle policy excludes. This integrates with the existing exemption tag work in Sprint 5. |
| L5 | **Cross-account parameter visibility**: AppTeam in prod cannot see what's in dev's parameter for debugging. | Add a read-only view in the central audit account (`/prasan-ins/ami/<app>/promotions` history) and surface it in the Cloud Platform self-service portal. |
| L6 | **Region scoping**: SSM parameters are regional. Multi-region workloads need parameters per region. | Make `region` a tag/key segment in the parameter path: `/prasan-ins/ami/<app>/<env>/<region>/current`. Promotion pipeline iterates regions. |
| L7 | **Image Builder native SSM integration was [released April 2025](https://aws.amazon.com/about-aws/whats-new/2025/04/ec2-image-builder-integrates-ssm-parameter-store/)** — relatively new feature. | Fall back pattern (well-established): EventBridge rule on Image Builder `state.status == AVAILABLE` event → Lambda → `ssm:PutParameter`. Use this if the native integration has gaps for cross-account writes in your region. |

---

## 4. Requirement #2 — ASG Patch Refresh Without Terraform Drift, Without App Team Deploys

### 4.1 Goal

> Platform-driven AMI rotation that replaces instances in an ASG **without** app team Terraform changes and **without** drift on the next `terraform plan`.

### 4.2 Two Viable Patterns — Pick One

This is genuinely a fork in the road. Both work; they make different trade-offs.

**Pattern B1 — `resolve:ssm:` in the launch template** *(recommended)*

The launch template stores a literal string like `resolve:ssm:/prasan-ins/ami/myapp/prod/current`. EC2 resolves this **at instance launch**, not at LT creation, not at TF plan. ([AWS docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-systems-manager-parameter-to-find-AMI.html); [Auto Scaling docs](https://docs.aws.amazon.com/autoscaling/ec2/userguide/using-systems-manager-parameters.html))

Why it's elegant:
- The string in the LT never changes when the AMI changes → **TF sees no drift, ever**.
- App team's TF doesn't need `ignore_changes`.
- Works with both `aws_launch_template` (Terraform AWS provider [supports it natively](https://github.com/hashicorp/terraform-provider-aws/issues/29637)) and CloudFormation.
- New instances always launch on whatever AMI the parameter currently resolves to. Existing instances are unchanged until refreshed.

**Pattern B2 — Concrete AMI ID + `lifecycle.ignore_changes` + platform-managed LT versions**

The LT is created with a concrete AMI ID. Platform Lambda calls `ec2:CreateLaunchTemplateVersion` to add new versions out-of-band. App team TF adds `lifecycle { ignore_changes = [image_id, default_version, latest_version] }` so it doesn't revert.

Why it has merit:
- Preserves the existing strategy doc rule "Use a concrete AMI ID; no dynamic references at runtime."
- Easier audit: each LT version is explicitly tied to a known AMI ID.
- Per-version rollback is mechanical (just point ASG at a previous LT version).

### 4.3 Comparison Table

| Dimension | B1 — `resolve:ssm:` | B2 — `ignore_changes` + platform LT versions |
|---|---|---|
| Terraform drift | None — image_id never changes | None — but only because of ignore_changes |
| App team TF complexity | Trivial (1 data source, 1 string) | Requires lifecycle block + understanding of why |
| New LT version per AMI rotation? | No (LT version stays constant) | Yes (new version per rotation, full audit trail) |
| Rollback mechanism | `ssm put-parameter` → trigger refresh | `aws autoscaling update-auto-scaling-group --launch-template Version=<old>` |
| `aws ec2 describe-launch-template-versions` shows AMI? | Use `--resolve-alias` flag, otherwise shows the SSM path string | Yes, native AMI ID |
| AWS Config rule eval (e.g. "LT must use approved AMI") | Needs to resolve the parameter; some rules don't natively | Direct — Config sees the AMI ID |
| Instance refresh trigger | Out-of-band (parameter change doesn't auto-refresh) | Out-of-band (LT version change doesn't auto-refresh either; Lambda still needed) |
| Audit story | Parameter change history is the audit trail | LT version history is the audit trail |
| Compatibility with existing strategy doc | **Conflicts** with Appendix B "no dynamic references at runtime" rule — needs explicit doc update | **Compatible** with existing rule |
| Risk of "stuck on old LT version" | Low — ASG always launches with current parameter value | Medium — ASG is pinned to a version; if Lambda fails to update default_version, ASG keeps using old |
| Cross-account complexity | SSM parameter must exist in the workload account (or use cross-account read, which is more expensive) | LT version creation is local to workload account |

**Recommendation: B1**, with Appendix B amended to read *"Use either a concrete AMI ID or an `ssm:` reference resolvable by EC2 at launch time. Dynamic Terraform-time lookups (e.g. `aws_ami` data source with `most_recent`) are still prohibited."* That preserves the original intent (no surprise plan-time changes) while enabling drift-free patching.

### 4.4 HLD — Requirement #2 (Pattern B1)

```xml
<mxGraphModel dx="1422" dy="762" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1500" pageHeight="900" math="0" shadow="0">
  <root>
    <mxCell id="0" />
    <mxCell id="1" parent="0" />

    <mxCell id="title" value="HLD — Requirement #2: Drift-Free AMI Refresh via resolve:ssm + EventBridge + Instance Refresh" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=15;fontStyle=1;" vertex="1" parent="1">
      <mxGeometry x="200" y="20" width="1100" height="30" as="geometry" />
    </mxCell>

    <!-- Workload Account -->
    <mxCell id="wl_acct" value="AWS Account — Workload (e.g. Prod)" style="points=[[0,0],[0.25,0],[0.5,0],[0.75,0],[1,0],[1,0.25],[1,0.5],[1,0.75],[1,1],[0.75,1],[0.5,1],[0.25,1],[0,1],[0,0.75],[0,0.5],[0,0.25]];shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_account;verticalLabelPosition=top;verticalAlign=bottom;fillColor=#FFEBEE;strokeColor=#C62828;fontStyle=1;fontSize=11;" vertex="1" parent="1">
      <mxGeometry x="60" y="80" width="1380" height="780" as="geometry" />
    </mxCell>

    <!-- Trigger: Promotion or Patch Cycle -->
    <mxCell id="trigger_box" value="Trigger Sources" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFF2CC;strokeColor=#D6B656;fontSize=11;fontStyle=1;verticalAlign=top;" vertex="1" parent="wl_acct">
      <mxGeometry x="40" y="40" width="280" height="160" as="geometry" />
    </mxCell>

    <mxCell id="t1" value="• Promotion pipeline (Req #1)&#10;• Image Builder pipeline (auto)&#10;• Out-of-cycle CVE patch&#10;• App team manual override" style="text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=top;whiteSpace=wrap;rounded=0;fontSize=11;" vertex="1" parent="wl_acct">
      <mxGeometry x="55" y="80" width="250" height="100" as="geometry" />
    </mxCell>

    <!-- SSM Parameter -->
    <mxCell id="ssm_param" value="SSM Parameter&#10;/prasan-ins/ami/&lt;app&gt;/&lt;env&gt;/current" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=10;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.systems_manager_parameter_store;" vertex="1" parent="wl_acct">
      <mxGeometry x="400" y="100" width="60" height="60" as="geometry" />
    </mxCell>

    <!-- EventBridge -->
    <mxCell id="eb" value="EventBridge Rule&#10;source=aws.ssm&#10;detail-type=Parameter Store Change&#10;name prefix=/prasan-ins/ami/" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=9;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.eventbridge;" vertex="1" parent="wl_acct">
      <mxGeometry x="600" y="100" width="60" height="60" as="geometry" />
    </mxCell>

    <!-- Step Functions -->
    <mxCell id="sfn" value="Step Function&#10;ami-refresh-orchestrator" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=10;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.step_functions;" vertex="1" parent="wl_acct">
      <mxGeometry x="800" y="100" width="60" height="60" as="geometry" />
    </mxCell>

    <!-- Lambda discover -->
    <mxCell id="lambda_discover" value="Lambda&#10;DiscoverAffectedASGs&#10;(tag-based query)" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=10;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.lambda;" vertex="1" parent="wl_acct">
      <mxGeometry x="1000" y="100" width="60" height="60" as="geometry" />
    </mxCell>

    <!-- Lambda preflight -->
    <mxCell id="lambda_preflight" value="Lambda&#10;PreflightChecks&#10;(maintenance window?&#10;exempt tag?)" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=9;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.lambda;" vertex="1" parent="wl_acct">
      <mxGeometry x="1200" y="100" width="60" height="60" as="geometry" />
    </mxCell>

    <!-- StartInstanceRefresh -->
    <mxCell id="ir_call" value="StartInstanceRefresh API&#10;(per ASG)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#D5E8D4;strokeColor=#82B366;fontSize=10;fontStyle=1;" vertex="1" parent="wl_acct">
      <mxGeometry x="1180" y="280" width="140" height="50" as="geometry" />
    </mxCell>

    <!-- ASG -->
    <mxCell id="asg" value="ASG&#10;(rolling refresh)" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=10;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.auto_scaling2;" vertex="1" parent="wl_acct">
      <mxGeometry x="1000" y="380" width="60" height="60" as="geometry" />
    </mxCell>

    <!-- LT -->
    <mxCell id="lt" value="Launch Template&#10;image_id = resolve:ssm:&#10;/prasan-ins/ami/myapp/prod/current" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFE6CC;strokeColor=#D79B00;fontSize=10;fontStyle=1;" vertex="1" parent="wl_acct">
      <mxGeometry x="800" y="380" width="160" height="60" as="geometry" />
    </mxCell>

    <!-- Old / New EC2 -->
    <mxCell id="old_ec2" value="Old EC2&#10;(ami-OLD)" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=10;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.ec2;" vertex="1" parent="wl_acct">
      <mxGeometry x="700" y="540" width="60" height="60" as="geometry" />
    </mxCell>

    <mxCell id="new_ec2" value="New EC2&#10;(ami-NEW)" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=10;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.ec2;" vertex="1" parent="wl_acct">
      <mxGeometry x="900" y="540" width="60" height="60" as="geometry" />
    </mxCell>

    <!-- ALB / health -->
    <mxCell id="alb" value="ALB Target Group&#10;health checks" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=10;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.application_load_balancer;" vertex="1" parent="wl_acct">
      <mxGeometry x="1100" y="540" width="60" height="60" as="geometry" />
    </mxCell>

    <!-- CW alarm -->
    <mxCell id="cw_alarm" value="CloudWatch Alarm&#10;(deployment health)&#10;auto-rollback trigger" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=9;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.cloudwatch_2;" vertex="1" parent="wl_acct">
      <mxGeometry x="1280" y="540" width="60" height="60" as="geometry" />
    </mxCell>

    <!-- SNS notify -->
    <mxCell id="sns" value="SNS&#10;Cloud Ops + App Team" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=10;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.simple_notification_service;" vertex="1" parent="wl_acct">
      <mxGeometry x="1100" y="700" width="60" height="60" as="geometry" />
    </mxCell>

    <!-- DDB state -->
    <mxCell id="ddb" value="DynamoDB&#10;refresh-state-tracker&#10;(idempotency key)" style="outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;fillColor=#FF9900;labelBackgroundColor=#ffffff;align=center;html=1;fontSize=10;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.dynamodb;" vertex="1" parent="wl_acct">
      <mxGeometry x="800" y="700" width="60" height="60" as="geometry" />
    </mxCell>

    <!-- Edges -->
    <mxCell id="x1" value="put-parameter" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="trigger_box" target="ssm_param" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="x2" value="emits event" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=open;dashed=1;fontSize=9;" edge="1" source="ssm_param" target="eb" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="x3" value="invokes" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="eb" target="sfn" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="x4" value="step 1" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="sfn" target="lambda_discover" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="x5" value="step 2" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="lambda_discover" target="lambda_preflight" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="x6" value="step 3" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="lambda_preflight" target="ir_call" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="x7" value="" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="ir_call" target="asg" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="x8" value="references" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="asg" target="lt" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="x9" value="resolves @ launch" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;dashed=1;fontSize=9;" edge="1" source="lt" target="ssm_param" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="x10" value="terminates" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="asg" target="old_ec2" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="x11" value="launches" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="asg" target="new_ec2" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="x12" value="health checks" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="alb" target="new_ec2" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="x13" value="watches" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=open;dashed=1;fontSize=9;" edge="1" source="cw_alarm" target="alb" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="x14" value="trips → rollback" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;strokeColor=#C62828;fontSize=9;fontStyle=1;" edge="1" source="cw_alarm" target="asg" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="x15" value="state" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;dashed=1;fontSize=9;" edge="1" source="sfn" target="ddb" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <mxCell id="x16" value="notifies" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;dashed=1;fontSize=9;" edge="1" source="sfn" target="sns" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

  </root>
</mxGraphModel>
```

### 4.5 LLD — Requirement #2 (Step Function definition, IAM, edge cases)

```xml
<mxGraphModel dx="1422" dy="762" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1500" pageHeight="950" math="0" shadow="0">
  <root>
    <mxCell id="0" />
    <mxCell id="1" parent="0" />

    <mxCell id="title" value="LLD — Requirement #2: Step Function State Machine + Guardrails" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=15;fontStyle=1;" vertex="1" parent="1">
      <mxGeometry x="350" y="20" width="800" height="30" as="geometry" />
    </mxCell>

    <!-- Step Function flow -->
    <mxCell id="start" value="Start&#10;(EventBridge input:&#10;parameter name + value)" style="ellipse;whiteSpace=wrap;html=1;fillColor=#D5E8D4;strokeColor=#82B366;fontSize=10;fontStyle=1;" vertex="1" parent="1">
      <mxGeometry x="100" y="100" width="160" height="60" as="geometry" />
    </mxCell>

    <mxCell id="s1" value="ParseEvent&#10;Lambda&#10;extract: app, env, ami_id" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFE6CC;strokeColor=#D79B00;fontSize=10;" vertex="1" parent="1">
      <mxGeometry x="100" y="200" width="160" height="60" as="geometry" />
    </mxCell>

    <mxCell id="s2" value="DiscoverASGs&#10;Lambda&#10;Tag filter: app, env, ami-lifecycle-managed=true" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFE6CC;strokeColor=#D79B00;fontSize=10;" vertex="1" parent="1">
      <mxGeometry x="100" y="300" width="160" height="70" as="geometry" />
    </mxCell>

    <mxCell id="s3" value="CheckExemption&#10;ami-lifecycle-exempt tag?&#10;ami-exempt-expiry valid?" style="rhombus;whiteSpace=wrap;html=1;fillColor=#FFE6CC;strokeColor=#D79B00;fontSize=10;" vertex="1" parent="1">
      <mxGeometry x="100" y="410" width="160" height="80" as="geometry" />
    </mxCell>

    <mxCell id="s4" value="CheckSSMCompliance&#10;Lambda&#10;(compensating control:&#10;PatchGroup compliance ≥ 95%)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFE6CC;strokeColor=#D79B00;fontSize=10;" vertex="1" parent="1">
      <mxGeometry x="100" y="540" width="160" height="80" as="geometry" />
    </mxCell>

    <mxCell id="s5" value="InMaintenanceWindow?&#10;cron schedule from&#10;asg-tag: maintenance-window" style="rhombus;whiteSpace=wrap;html=1;fillColor=#FFE6CC;strokeColor=#D79B00;fontSize=10;" vertex="1" parent="1">
      <mxGeometry x="100" y="660" width="160" height="80" as="geometry" />
    </mxCell>

    <mxCell id="s6" value="Defer (wait state)&#10;reschedule until&#10;next window" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#F8CECC;strokeColor=#B85450;fontSize=10;" vertex="1" parent="1">
      <mxGeometry x="320" y="660" width="140" height="60" as="geometry" />
    </mxCell>

    <mxCell id="s7" value="StartInstanceRefresh&#10;Map state: parallel per ASG&#10;preferences:&#10;  min_healthy=50%&#10;  auto_rollback=true&#10;  alarm_specification=set" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFE6CC;strokeColor=#D79B00;fontSize=10;" vertex="1" parent="1">
      <mxGeometry x="100" y="780" width="160" height="100" as="geometry" />
    </mxCell>

    <mxCell id="s8" value="WaitForCompletion&#10;poll DescribeInstanceRefreshes&#10;timeout: 90 min" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFE6CC;strokeColor=#D79B00;fontSize=10;" vertex="1" parent="1">
      <mxGeometry x="500" y="780" width="160" height="80" as="geometry" />
    </mxCell>

    <mxCell id="s9" value="Successful?" style="rhombus;whiteSpace=wrap;html=1;fillColor=#FFE6CC;strokeColor=#D79B00;fontSize=10;" vertex="1" parent="1">
      <mxGeometry x="710" y="780" width="100" height="80" as="geometry" />
    </mxCell>

    <mxCell id="s10" value="UpdateLKG&#10;put /prasan-ins/ami/&lt;app&gt;/&lt;env&gt;/previous&#10;= old AMI" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#D5E8D4;strokeColor=#82B366;fontSize=10;" vertex="1" parent="1">
      <mxGeometry x="860" y="700" width="160" height="80" as="geometry" />
    </mxCell>

    <mxCell id="s11" value="Notify Success&#10;SNS → Cloud Ops + App Team" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#D5E8D4;strokeColor=#82B366;fontSize=10;" vertex="1" parent="1">
      <mxGeometry x="1080" y="700" width="160" height="60" as="geometry" />
    </mxCell>

    <mxCell id="s12" value="RollbackHandled&#10;ASG auto-rollback completed&#10;OR escalate to PagerDuty" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#F8CECC;strokeColor=#B85450;fontSize=10;" vertex="1" parent="1">
      <mxGeometry x="860" y="850" width="160" height="80" as="geometry" />
    </mxCell>

    <mxCell id="s13" value="LogToDDB + SNS Alert" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#F8CECC;strokeColor=#B85450;fontSize=10;" vertex="1" parent="1">
      <mxGeometry x="1080" y="850" width="160" height="60" as="geometry" />
    </mxCell>

    <!-- Edges -->
    <mxCell id="f1" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="start" target="s1" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
    <mxCell id="f2" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="s1" target="s2" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
    <mxCell id="f3" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="s2" target="s3" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
    <mxCell id="f4" value="not exempt" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="s3" target="s4" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
    <mxCell id="f5" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="s4" target="s5" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
    <mxCell id="f6" value="yes" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="s5" target="s7" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
    <mxCell id="f7" value="no" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="s5" target="s6" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
    <mxCell id="f8" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="s7" target="s8" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
    <mxCell id="f9" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="s8" target="s9" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
    <mxCell id="f10" value="yes" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="s9" target="s10" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
    <mxCell id="f11" value="no" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;strokeColor=#B85450;fontSize=9;" edge="1" source="s9" target="s12" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
    <mxCell id="f12" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;fontSize=9;" edge="1" source="s10" target="s11" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>
    <mxCell id="f13" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;endFill=1;strokeColor=#B85450;fontSize=9;" edge="1" source="s12" target="s13" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

  </root>
</mxGraphModel>
```

### 4.6 Terraform pattern — Pattern B1 launch template

```hcl
resource "aws_launch_template" "this" {
  name_prefix   = "${var.app_name}-${var.environment}-"
  # The literal string is what's stored. EC2 resolves it at instance launch.
  image_id      = "resolve:ssm:/prasan-ins/ami/${var.app_name}/${var.environment}/current"
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.this.arn
  }

  # Required so EC2 can call ssm:GetParameters when resolving (caller's perms)
  # In practice the LT IAM role + the principal calling RunInstances/ASG launch
  # both need ssm:GetParameter on this path. Cover both via a dedicated
  # resolve-policy attached to the ASG service-linked role and the launch-time role.

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      "ami-lifecycle-managed" = "true"
      "app"                   = var.app_name
      "env"                   = var.environment
    })
  }

  lifecycle {
    create_before_destroy = true
    # NOTE: image_id needs no ignore_changes — it never changes in TF state
  }
}
```

The string `resolve:ssm:/prasan-ins/ami/myapp/prod/current` is what `terraform plan` will show forever. Platform pushes new AMI IDs to the SSM parameter all day long; Terraform never sees a difference.

### 4.7 EventBridge rule + Step Function trigger (Terraform)

```hcl
resource "aws_cloudwatch_event_rule" "ami_param_change" {
  name = "prasan-ins-ami-param-change"
  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["Parameter Store Change"]
    detail = {
      name      = [{ "prefix": "/prasan-ins/ami/" }]
      operation = ["Update"]
    }
  })
}

resource "aws_cloudwatch_event_target" "to_sfn" {
  rule     = aws_cloudwatch_event_rule.ami_param_change.name
  arn      = aws_sfn_state_machine.ami_refresh.arn
  role_arn = aws_iam_role.eb_invoke_sfn.arn

  input_transformer {
    input_paths = {
      param_name = "$.detail.name"
      param_op   = "$.detail.operation"
      account    = "$.account"
      region     = "$.region"
    }
    input_template = <<EOF
{
  "param_name": <param_name>,
  "operation": <param_op>,
  "account": <account>,
  "region": <region>
}
EOF
  }
}
```

### 4.8 Limitations & Trade-offs (Requirement #2)

| # | Limitation | Mitigation |
|---|---|---|
| L8 | `resolve:ssm:` resolves only at **instance launch**. Existing instances continue running the old AMI until refreshed. | This is by design — ASG instance refresh is what actually rotates them. Document explicitly so app teams understand "parameter change ≠ rotation." |
| L9 | The principal that launches instances (the ASG service-linked role + any role assumed during launch) needs `ssm:GetParameter` on the path. In some hardened landing zones, SCP denies SSM access broadly. | Add an explicit allow for `ssm:GetParameter` on `/prasan-ins/ami/*` in the boundary policy for ASG SLR, or use a parameter ARN form to make permissioning narrower. |
| L10 | **Self-healing scale-out** during a failed refresh: if the new AMI is bad and ASG auto-rollback is in progress, but a scale-out event triggers (e.g. CPU alarm), new instances launched will use the *new* (bad) AMI because the parameter hasn't reverted. | Step Function rollback step writes the previous AMI back to the parameter, then triggers refresh. Two-step: revert parameter → start instance refresh on the old value. The LKG (`/previous`) parameter exists exactly for this. |
| L11 | **AWS Config rule evaluations** that check "EC2 instance must use approved AMI" may not natively follow `resolve:ssm:` — they see the parameter string, not the AMI ID, on the LT. | Use a custom Config rule that resolves the parameter and validates the underlying AMI. Or evaluate at the EC2 instance level (which has the resolved AMI ID) instead of at the LT level. |
| L12 | EventBridge `Parameter Store Change` events are emitted for every put — including no-op updates where value didn't change. Could trigger unnecessary refreshes. | First step in Step Function compares incoming value to last-recorded value in DynamoDB; short-circuits if equal. Idempotency by `(asg_arn, ami_id)`. |
| L13 | **Concurrent refresh limit**: an ASG can have only one in-progress refresh. If another fires before the first completes, it'll fail with `InstanceRefreshInProgressFault`. | Step Function checks `DescribeInstanceRefreshes` before starting; if one is in progress, queue via SQS FIFO with the ASG ARN as MessageGroupId. |
| L14 | **Cross-account SSM parameter resolution** — if you wanted *one* parameter in central account read by all workload accounts, that's not natively supported by `resolve:ssm:`. The parameter must be in the same account/region as the LT. | This is fine for the recommended design — each workload account has its own parameter, written by Image Builder distribution config (which natively supports cross-account writes) or the promotion pipeline. |
| L15 | The strategy doc Appendix B says "Use a concrete AMI ID; no dynamic references at runtime." Pattern B1 violates this. | Amend Appendix B (proposed wording in §4.3 above). Frame the change as: "static at TF time, dynamic at launch time" — preserves the original intent of TF determinism. |
| L16 | Some app teams may already have ASGs not tagged with `ami-lifecycle-managed=true`. Discovery Lambda will skip them. | Sprint 6 ASG inventory + bulk re-tagging campaign. Pair with the Sprint 5 exemption tag work — `ami-lifecycle-exempt=true` + `ami-lifecycle-managed=true` are not mutually exclusive (managed but exempt = patched in place via SSM). |

---

## 5. Combined Architecture — How Both Requirements Work Together

The two patterns lock cleanly together. The same SSM parameter is the integration point:

- **Image Builder** writes to `/prasan-ins/ami/<app>/dev/current` (Req #1 distribution config).
- **Promotion pipeline** writes to `/prasan-ins/ami/<app>/preprod/current` and `…/prod/current` (Req #1 promotion).
- **EventBridge → Step Function → ASG Instance Refresh** kicks in *every time* any of those parameters changes (Req #2 mechanism).
- **Launch templates** in every account use `resolve:ssm:…/<env>/current` (Req #2 reference).

The combined flow for a single weekly cycle:

1. Image Builder publishes a new AMI on Monday → distribution writes to dev parameter.
2. EventBridge fires → Step Function refreshes dev ASGs (during dev maintenance window).
3. Dev validation pipeline runs over Tue–Wed → if green, triggers promotion to preprod.
4. Promotion pipeline writes preprod parameter on Thursday → EventBridge fires → preprod ASGs refreshed.
5. Preprod validation runs Thursday–Friday → manual gate over weekend → prod parameter updated Monday → prod ASGs refreshed.

App teams' Terraform was applied **once** (during onboarding). After that, they consume *patched, validated, environment-locked* AMIs without doing anything.

---

## 6. Open Decisions for Sprint Planning

These need a call before this is finalized:

1. **Appendix B amendment.** Are we OK evolving the rule to allow `resolve:ssm:` references? (Recommended: yes, with the wording in §4.3.)
2. **Promotion approval gates.** Is preprod → prod always behind a manual gate, or auto-promote with N-day soak?
3. **LKG storage location.** Doc says workload-owned. Suggest co-locating LKG as `/prasan-ins/ami/<app>/<env>/previous` SSM parameter rather than per-app implementations. Easier rollback Lambda; consistent runbook.
4. **What happens if dev validation never succeeds?** Aging promotion alarm fires after 14 days — but does prod get force-rolled to a CVE-critical AMI even without validation? (Probably yes for sev-1 CVEs; need a "break glass" override path.)
5. **Patch-in-place exemption interaction.** When an ASG has `ami-lifecycle-exempt=true`, the Step Function skips it. But the SSM parameter may still update, which means a *scale-out* event launches a new instance on the new AMI. Is that the intended behavior? (I think yes — exemption means "don't force refresh existing instances," not "don't use new AMI for new instances." Worth confirming with InfoSec.)
6. **Region scoping** of parameters — do we want `/prasan-ins/ami/<app>/<env>/current` (region implicit) or `/prasan-ins/ami/<app>/<env>/<region>/current` (explicit)? Recommend explicit even for single-region today.
7. **Image Builder native SSM distribution vs Lambda glue.** The native feature is from April 2025 — fine for greenfield, but verify it works in our region and supports cross-account writes the way we want.

---

## 7. Recommended Sprint Slotting

| Sprint | Work item |
|---|---|
| Sprint 5 (in flight) | (a) Add SSM parameter schema as a sub-task; (b) update Appendix B wording; (c) extend exemption tag design to include `ami-lifecycle-managed` boolean for opt-in. |
| Sprint 6 | (a) Build promotion pipeline (GitLab) as TFE module; (b) build Step Function + Lambdas in central operations account; (c) Terraform module for app team `aws_launch_template` with `resolve:ssm:`. |
| Sprint 7 | (a) ASG inventory & re-tagging campaign; (b) onboard 2–3 pilot apps end-to-end; (c) runbook updates for promotion failure, refresh failure, and exemption granting. |

---

## 8. References

- AWS docs — [Use AWS Systems Manager parameters instead of AMI IDs in launch templates](https://docs.aws.amazon.com/autoscaling/ec2/userguide/using-systems-manager-parameters.html)
- AWS docs — [Reference AMIs using Systems Manager parameters](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-systems-manager-parameter-to-find-AMI.html)
- AWS docs — [EC2 Image Builder distribution: SSM parameter configurations](https://docs.aws.amazon.com/imagebuilder/latest/userguide/cr-upd-ami-distribution-settings.html)
- AWS docs — [EC2 Image Builder lifecycle policies](https://docs.aws.amazon.com/imagebuilder/latest/userguide/manage-lifecycle.html)
- AWS What's New — [EC2 Image Builder integrates with SSM Parameter Store (Apr 2025)](https://aws.amazon.com/about-aws/whats-new/2025/04/ec2-image-builder-integrates-ssm-parameter-store/)
- AWS Blog — [Using Systems Manager Parameter as an alias for AMI ID](https://aws.amazon.com/blogs/compute/using-system-manager-parameter-as-an-alias-for-ami-id/)
- Terraform AWS provider — [aws_launch_template resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) (supports `resolve:ssm:` in `image_id`, see [issue #29637](https://github.com/hashicorp/terraform-provider-aws/issues/29637))
- AWS Samples — [Elastic Beanstalk Image Pipeline Trigger](https://github.com/aws-samples/elastic-beanstalk-image-pipeline-trigger) (Lambda fallback pattern for Image Builder → SSM)
