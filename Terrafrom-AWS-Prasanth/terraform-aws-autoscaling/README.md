# terraform-aws-autoscaling

Placeholder README.

This module was reconstructed from screenshots. Replace this file with the original documentation when available.

## In-place patching capacity

This module tags the Auto Scaling Group with `PatchGroup = asg` by default and propagates
it to the instances, so Systems Manager Patch Manager targets them for Standby-based
in-place patching.

Because Patch Manager moves one instance into Standby and decrements desired capacity to
do so, an ASG that opts into this pattern must have capacity headroom:

```text
desired_capacity >= min_size + 1
```

This is enforced two ways:

| Mechanism | Location | Behaviour |
| --- | --- | --- |
| `validation` block | `variables.tf` (`desired_capacity`) | Hard-fails `plan`/`apply` on bad module inputs |
| `check` block | `checks.tf` | Warns when the *live* ASG drifts out of compliance |

### Capacity validation summary

| Rule | Applies when |
| --- | --- |
| `min_size` is a non-negative integer | always |
| `max_size` is a non-negative integer | always |
| `desired_capacity` is a non-negative integer | always |
| `max_size >= min_size` | always |
| `desired_capacity <= max_size` | always |
| `desired_capacity >= min_size + 1` | `enable_patch_group_asg = true` |

Only the last rule is patching-specific. Scale-to-zero (`0/0/0`, or `0/4/0` for a parked
batch pool) therefore remains valid on ASGs that opt out of patching, while a
patching-enabled ASG picks up an effective floor of one instance for free —
`min_size >= 0` combined with `desired_capacity >= min_size + 1` already implies
`desired_capacity >= 1`, so no separate rule is needed for it.

See **[USAGE.md](USAGE.md)** for every capacity pattern crossed against the patching flag,
sizing recipes, drift scenarios, and worked examples.

The `check` block reads the deployed Auto Scaling Group rather than the input variables, so
it also catches capacity changed outside Terraform (console edits, scaling policies) that
the input validation cannot see.

To exclude an ASG from this pattern, opt out explicitly — the capacity rule is then not
enforced and fixed sizing such as `1/1/1` remains valid:

```hcl
enable_patch_group_asg = false
```

> **Note**
>
> Asserting only `min_size != max_size` is **not** sufficient. A config of
> `min 1 / max 2 / desired 1` passes that check but still cannot enter Standby, because
> desired capacity would drop below `min_size`. `max_size` is irrelevant to this rule:
> Standby moves desired capacity *downward*, so only the gap between `desired_capacity`
> and `min_size` determines whether patching can proceed.

## Design rationale

Three alternatives were considered and rejected. Recorded here because each one looks
simpler than what was implemented, and the reasons they fail are not obvious by inspection.

### 1. Why not assert `min_size != max_size`?

`min_size != max_size` is a strictly weaker approximation of the real constraint. It never
wrongly rejects a working config, but it lets through a whole class of ASGs that cannot
patch — any group sitting at `desired == min` with room to scale out.

| min/max/desired | `min != max` | `desired >= min + 1` | Can actually patch? |
| --- | --- | --- | --- |
| `1/1/1` | reject | reject | No |
| `2/2/2` | reject | reject | No |
| `1/2/1` | **pass** | reject | **No** — false green |
| `2/4/2` | **pass** | reject | **No** — false green |
| `1/2/2` | pass | pass | Yes |
| `2/3/3` | pass | pass | Yes |

`2/4/2` is not a contrived edge case — it is the ordinary "scale out under load, sit at
minimum at rest" shape, and it is exactly where a false green hurts most: the guardrail
reports healthy while patching silently never runs, which is the original problem this
work set out to fix.

The two rules agree whenever `min == max`, because `min <= desired <= max` forces
`desired == min` there. All the divergence is in the `min != max` cases above.

Note that `min != max` still ends up enforced for patching-enabled ASGs — it is just
*derived* rather than asserted. Combining `desired_capacity <= max_size` with
`desired_capacity >= min_size + 1` transitively gives `max_size >= min_size + 1`. The
underlying intuition was sound; only the choice of it as the primary assertion was not.

### 2. Why a `enable_patch_group_asg` flag instead of reading the `PatchGroup` tag?

Keying the rule off a user-supplied tag value (`lookup(var.asg_tags, "PatchGroup", "") == "asg"`)
fails open in several ways:

- **Typos silently disable the guardrail.** `patchgroup`, `Patch_Group`, or `PatchGroup = "ASG"`
  all skip the validation entirely while the operator believes patching is configured.
- **It only sees one of the two places the tag can live.** A validation reading `var.asg_tags`
  cannot see a tag set through `tag_specifications` on the launch template — and
  [examples/complete/main.tf](examples/complete/main.tf) did exactly that before this change.
  The guardrail would have been invisible on a correctly-tagged ASG.
- **It inverts the requested default.** No tag means no validation, so patching becomes
  opt-in. The requirement was patching on by default unless a team deliberately opts out.

Having the module own the tag collapses "is this ASG tagged for patching" and "is this ASG
validated for patching" into a single fact that cannot drift apart.

### 3. Why not a `check` block *instead of* variable validation?

`check` blocks do not fail `terraform apply` — a failed `assert` emits a warning and the
apply succeeds. For a rule whose entire purpose is preventing a silent patching failure, a
warning in CI output reproduces the same failure mode one level up: nobody notices, and the
instances still go unpatched.

`check` blocks do have a capability validation lacks — they read deployed resource state and
re-evaluate on every plan, so they catch drift. The two are therefore used for different
jobs rather than as substitutes:

- `validation` gates the **inputs** and blocks bad config from ever applying.
- `check` watches the **live ASG** and warns when capacity is changed outside Terraform.

This is also why [checks.tf](checks.tf) asserts against `aws_autoscaling_group.main` rather
than against the variables. A `check` block reading the same variables would be dead code —
validation fails first, the plan aborts, and the assert never evaluates.

### Migration cost

This is a breaking change for existing fixed-capacity ASGs. A `1/1/1` group that picks up
this module version starts failing `plan`, and must either gain capacity headroom or set
`enable_patch_group_asg = false`. That cost is deliberate: those groups were never being
patched, and the failure was previously silent.
