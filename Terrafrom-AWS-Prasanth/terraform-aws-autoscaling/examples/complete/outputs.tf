output "autoscaling" {
  description = "Outputs of the Auto Scaling Group"

  value = {
    launch_template_id             = module.autoscaling.launch_template_id
    launch_template_arn            = module.autoscaling.launch_template_arn
    launch_template_latest_version = module.autoscaling.launch_template_latest_version

    autoscaling_group_id   = module.autoscaling.autoscaling_group_id
    autoscaling_group_name = module.autoscaling.autoscaling_group_name
    autoscaling_group_arn  = module.autoscaling.autoscaling_group_arn

    autoscaling_policy_arns = module.autoscaling.autoscaling_policy_arns
  }
}

output "autoscaling_use1" {
  description = "Outputs of the Auto Scaling Group in USE1"

  value = {
    launch_template_id             = module.autoscaling_use1.launch_template_id
    launch_template_arn            = module.autoscaling_use1.launch_template_arn
    launch_template_latest_version = module.autoscaling_use1.launch_template_latest_version

    autoscaling_group_id   = module.autoscaling_use1.autoscaling_group_id
    autoscaling_group_name = module.autoscaling_use1.autoscaling_group_name
    autoscaling_group_arn  = module.autoscaling_use1.autoscaling_group_arn

    autoscaling_policy_arns = module.autoscaling_use1.autoscaling_policy_arns
  }
}
