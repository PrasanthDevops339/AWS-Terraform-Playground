check "in_place_patching_capacity" {
  assert {
    condition = !var.enable_patch_group_asg || try(
      one(aws_autoscaling_group.main).desired_capacity >= one(aws_autoscaling_group.main).min_size + 1,
      true
    )

    error_message = <<-EOT
      Live Auto Scaling Group capacity cannot support PatchGroup=asg in-place patching.
      Required: desired_capacity >= min_size + 1 (for example 1/2/2, 2/3/3, 3/4/4).

      Patch Manager moves one instance into Standby, which decrements desired capacity.
      With no headroom above min_size the instance never reaches Standby and patching
      silently never runs.

      This warning reflects the Auto Scaling Group's current state, so it also fires when
      capacity was changed outside Terraform (for example in the console or by a scaling
      policy) even though the module inputs are still valid.
    EOT
  }
}
