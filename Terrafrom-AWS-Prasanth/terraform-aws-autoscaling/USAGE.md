# Usage: ASG capacity and the patching flag

Every combination of Auto Scaling Group capacity and `enable_patch_group_asg`, what
Terraform does with it, and whether Systems Manager Patch Manager can actually patch it.

Capacity is written throughout as `min / max / desired`.

## The rules being applied

| # | Rule | Applies when |
| --- | --- | --- |
| 1 | `min_size` is a non-negative integer | always |
| 2 | `max_size` is a non-negative integer | always |
| 3 | `desired_capacity` is a non-negative integer | always |
| 4 | `max_size >= min_size` | always |
| 5 | `desired_capacity <= max_size` | always |
| 6 | `desired_capacity >= min_size + 1` | `enable_patch_group_asg = true` |

Rules 1–5 are ordinary ASG sanity. Only rule 6 is patching-specific, and only rule 6 is
skipped when you opt out.

## Master matrix

| Shape | `min/max/desired` | `enable_patch_group_asg = true` (default) | `enable_patch_group_asg = false` |
| --- | --- | --- | --- |
| Fixed | `1/1/1` | ❌ plan fails (rule 6) | ✅ applies, never patched |
| Fixed | `2/2/2` | ❌ plan fails (rule 6) | ✅ applies, never patched |
| Fixed | `3/3/3` | ❌ plan fails (rule 6) | ✅ applies, never patched |
| Desired at min | `1/2/1` | ❌ plan fails (rule 6) | ✅ applies, never patched |
| Desired at min | `2/4/2` | ❌ plan fails (rule 6) | ✅ applies, never patched |
| Headroom | `0/1/1` | ✅ applies, patches | ✅ applies, never patched |
| Headroom | `1/2/2` | ✅ applies, patches | ✅ applies, never patched |
| Headroom | `2/3/3` | ✅ applies, patches | ✅ applies, never patched |
| Headroom | `3/4/4` | ✅ applies, patches | ✅ applies, never patched |
| Headroom + burst | `2/6/3` | ✅ applies, patches | ✅ applies, never patched |
| Parked | `0/0/0` | ❌ plan fails (rule 6) | ✅ applies, nothing to patch |
| Scale-to-zero | `0/4/0` | ❌ plan fails (rule 6) | ✅ applies, nothing to patch |
| Inverted | `2/1/1` | ❌ plan fails (rule 4) | ❌ plan fails (rule 4) |
| Over max | `1/2/3` | ❌ plan fails (rule 5) | ❌ plan fails (rule 5) |
| Fractional | `1/2/1.5` | ❌ plan fails (rule 3) | ❌ plan fails (rule 3) |
| Negative | `-1/2/2` | ❌ plan fails (rule 1) | ❌ plan fails (rule 1) |

The `enable_patch_group_asg = false` column fails only on rules 1–5, which are structural
ASG errors that AWS would reject anyway. Opting out never rescues an invalid ASG — it only
waives rule 6.

## Why the rejected patterns fail

### Fixed capacity — `1/1/1`, `2/2/2`, `3/3/3`

The most common app-team shape, and the reason this validation exists.

Patch Manager moves an instance into Standby with `ShouldDecrementDesiredCapacity = true`.
On a `2/2/2` group that decrement would take desired capacity to 1, below `min_size` of 2,
so Auto Scaling rejects it. The instance never reaches Standby, the patch step never runs,
and **nothing reports an error** — the maintenance window simply completes having patched
nothing.

### Desired sitting at minimum — `1/2/1`, `2/4/2`

These have a `max_size` above `min_size`, so they look patchable, but `max_size` is
irrelevant to this operation. `max_size` caps scaling *out*; Standby moves desired capacity
*down*. With `desired == min` there is no downward room, so the outcome is identical to the
fixed-capacity case.

`2/4/2` is the ordinary "scale out under load, sit at minimum at rest" configuration, which
is why this class matters more than it first appears.

### Zero capacity — `0/0/0`, `0/4/0`

There are no running instances to patch, so `PatchGroup = asg` is meaningless. Set
`enable_patch_group_asg = false` on parked or scale-to-zero groups.

## Supported patterns in detail

| `min/max/desired` | Serving normally | Serving during patching | Notes |
| --- | --- | --- | --- |
| `0/1/1` | 1 | 0 | Module default. Tolerates a full outage while patching. |
| `1/2/2` | 2 | 1 | Smallest shape that stays up during patching. |
| `2/3/3` | 3 | 2 | |
| `3/4/4` | 4 | 3 | |
| `2/6/3` | 3 | 2 | Headroom for patching plus room to scale out to 6. |

### Sizing recipe

To keep **K** instances serving at all times, including mid-patch:

```text
min_size         = K
max_size         = K + 1
desired_capacity = K + 1
```

One instance is in Standby for the duration of its patch and reboot, so a group always
serves one fewer instance than `desired_capacity` while patching is in progress. Size for
`K`, not for `desired_capacity`.

`0/1/1` is the exception worth calling out: it passes validation and does patch correctly,
but drops to zero serving instances while its single instance is in Standby. Fine for
workers and batch, not for anything behind a load balancer.

## Worked examples

Standard patched web tier, staying up throughout:

```hcl
module "autoscaling" {
  source = "..."

  min_size         = 2
  max_size         = 3
  desired_capacity = 3

  # enable_patch_group_asg defaults to true
}
```

Deliberately excluded from ASG-pattern patching, fixed capacity:

```hcl
module "autoscaling" {
  source = "..."

  min_size         = 1
  max_size         = 1
  desired_capacity = 1

  enable_patch_group_asg = false
}
```

Scale-to-zero batch pool:

```hcl
module "autoscaling" {
  source = "..."

  min_size         = 0
  max_size         = 4
  desired_capacity = 0

  enable_patch_group_asg = false
}
```

Migrating an existing `2/2/2` group onto patching. Raise `max_size` and `desired_capacity`
together in a single apply — raising `max_size` alone leaves `desired == min` and still
fails rule 6:

```text
before        2/2/2   ❌ fails rule 6
max only      2/3/2   ❌ still fails rule 6 — desired is still at min
after         2/3/3   ✅
```

```hcl
module "autoscaling" {
  source = "..."

  min_size         = 2
  max_size         = 3
  desired_capacity = 3
}
```

There is no need to sequence this across two applies. Terraform validates inputs before
making any AWS calls, so a rejected plan changes nothing and the group is never left in an
intermediate invalid state.

## Drift: when a valid config stops being patchable

Rule 6 validates *inputs*. The `check` block in [checks.tf](checks.tf) validates the
*live* group on every plan, and warns without blocking. These are the cases it catches.

| Scenario | Live result | Behaviour |
| --- | --- | --- |
| Scale-in policy reduces `1/2/2` to desired 1 | `desired == min` | ⚠️ check warns |
| Console edit raises `min_size` on `1/2/2` to 2 | `desired == min` | ⚠️ check warns |
| Manual console change to `2/2/2` | `desired == min` | ⚠️ check warns |
| Group scaled out to desired 4 on `2/6/3` | headroom intact | no warning |

The scaling-policy case is the important one. A group can pass validation at apply time and
then be scaled in to its minimum by its own `scaling_policies`, at which point it silently
stops being patchable. No input changed, so variable validation cannot see it. Running
`terraform plan` surfaces the warning.

## Caveats

**The rule assumes one instance patched at a time.** `desired_capacity >= min_size + 1`
provides room for exactly one Standby instance. If your maintenance window or SSM automation
runs with concurrency greater than 1, several instances attempt Standby simultaneously and
you need `desired_capacity >= min_size + concurrency`. The module cannot see your
maintenance window configuration, so it cannot validate this — size accordingly.

**Opting out does not remove a hand-written tag.** Setting `enable_patch_group_asg = false`
stops the *module* from adding `PatchGroup = asg`, but if you also pass
`PatchGroup = "asg"` yourself through `asg_tags`, the module still propagates it to the
instances and Patch Manager still targets them — with rule 6 no longer enforcing the
capacity headroom they need. Do not combine the two. Use the flag, not a manual tag.

**Rule 6 is a breaking change for existing groups.** A fixed-capacity ASG that picks up this
module version starts failing `plan` and must either gain headroom or opt out. See
[README.md](README.md#migration-cost).
