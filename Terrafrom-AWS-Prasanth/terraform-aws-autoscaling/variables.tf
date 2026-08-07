##############################
# Launch template variables
##############################

variable "create_lt" {
  description = "Set True to create launch template"
  type        = bool
  default     = true
}

variable "create_asg" {
  description = "Set True to create Auto scaling group"
  type        = bool
  default     = true
}

variable "launch_template_name" {
  description = "Name of the Launch template."
  type        = string
}

variable "template_description" {
  description = "Description of the launch template."
  type        = string
}

variable "ami_id" {
  description = "The AMI from which to launch the instance."
  type        = string
}

variable "instance_type" {
  description = "The type of ec2 instance"
  type        = string
  default     = "t2.micro"
}

variable "user_data" {
  description = "The Base64-encoded user data to provide when launching the instance"
  type        = string
  default     = null
}

variable "iam_instance_profile" {
  description = "The instance profile name"
  type        = string
  default     = ""
}

variable "vpc_security_group_ids" {
  description = "A list of security group IDs to associate with ec2"
  default     = []
}

variable "block_device_mappings" {
  description = "Specify volumes to attach to the instance besides the volumes specified by the AMI"
  type        = list(any)
  default     = []
}

variable "kms_key_id" {
  description = "The ARN of the AWS Key Management Service (AWS KMS) customer master key (CMK) to use when creating the encrypted volume. encrypted must be set to true"
  type        = string
}

variable "enable_monitoring" {
  description = "Enables/disables detailed monitoring"
  type        = bool
  default     = true
}

variable "update_default_version" {
  description = "Determines if the Default Version is updated"
  type        = bool
  default     = true
}

variable "tag_specifications" {
  description = "Sets tag specifications for different resources"
  type        = list(any)
  default     = []
}

##############################
# AutoScaling Group variables
##############################

variable "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  type        = string
}

variable "subnet_type" {
  description = "The VPC subnet type to launch resources in. Available values are: app, web"
  type        = string
  default     = "app"

  validation {
    condition     = length(var.subnet_type) >= 3 && !strcontains(var.subnet_type, "dat")
    error_message = "Subnet type must be at least 3 characters and not contain 'dat'."
  }
}

variable "enable_patch_group_asg" {
  description = "Tag the Auto Scaling Group with PatchGroup=asg (propagated to instances) so Systems Manager Patch Manager targets it for Standby-based in-place patching. Set to false only to deliberately exclude this ASG from ASG-pattern patching."
  type        = bool
  default     = true
}

variable "desired_capacity" {
  description = "Number of Amazon EC2 instances that should be running in the group."
  type        = number
  default     = 1

  validation {
    condition     = var.desired_capacity >= 0 && floor(var.desired_capacity) == var.desired_capacity
    error_message = "Invalid desired_capacity: the value must be a non-negative integer."
  }

  validation {
    condition     = var.desired_capacity <= var.max_size
    error_message = "Invalid ASG capacity: desired_capacity must be less than or equal to max_size."
  }

  validation {
    condition     = !var.enable_patch_group_asg || var.desired_capacity >= var.min_size + 1
    error_message = <<-EOT
      Auto Scaling Group capacity is too tight for PatchGroup=asg in-place patching.
      Required: desired_capacity >= min_size + 1 (for example 1/2/2, 2/3/3, 3/4/4).

      Patch Manager moves one instance into Standby, which decrements desired capacity.
      Without headroom above min_size that decrement is rejected, the instance never
      reaches Standby, and patching silently never runs. Fixed configurations such as
      1/1/1, 2/2/2 or 3/3/3 therefore always fail to patch.

      Note: asserting only min_size != max_size is NOT sufficient and is not recommended.
      A config of min 1 / max 2 / desired 1 passes that check yet still cannot enter
      Standby, because desired capacity would drop below min_size. The max_size value is
      irrelevant here: Standby decrements desired capacity downward, so only the gap
      between desired_capacity and min_size determines whether patching can proceed.

      Set enable_patch_group_asg = false if this ASG is deliberately excluded from patching.
    EOT
  }
}

variable "max_size" {
  description = "(Required) Maximum size of the Auto Scaling Group"
  type        = number
  default     = 1

  validation {
    condition     = var.max_size >= 0 && floor(var.max_size) == var.max_size
    error_message = "Invalid max_size: the value must be a non-negative integer."
  }

  validation {
    condition     = var.max_size >= var.min_size
    error_message = "Invalid ASG capacity: max_size must be greater than or equal to min_size."
  }
}

variable "min_size" {
  description = "(Required) Minimum size of the Auto Scaling Group"
  type        = number
  default     = 0

  validation {
    condition     = var.min_size >= 0 && floor(var.min_size) == var.min_size
    error_message = "Invalid min_size: the value must be a non-negative integer."
  }
}

variable "health_check_type" {
  description = "EC2 or ELB. Controls how health checking is done."
  type        = string
  default     = "ELB"
}

variable "health_check_grace_period" {
  description = "Time (in seconds) after instance comes into service before checking health."
  type        = number
  default     = 300
}

variable "default_cooldown" {
  description = "Amount of time, in seconds, after a scaling activity completes before another scaling activity can start."
  type        = string
  default     = "300"
}

variable "instance_warmup" {
  description = "Amount of time, in seconds, until a newly launched instance can contribute to the Amazon CloudWatch metrics."
  type        = number
  default     = 10
}

variable "target_group_arns" {
  description = "A set of aws_alb_target_group ARNs, for use with Application or Network Load Balancing"
  type        = list(string)
  default     = []
}

variable "launch_template_version" {
  description = "default version"
  type        = string
  default     = "$Latest"
}

variable "enabled_metrics" {
  description = "A list of metrics to collect."
  type        = list(string)
  default     = []
}

variable "initial_lifecycle_hooks" {
  description = "One or more Lifecycle Hooks to attach to the Auto Scaling Group before instances are launched."
  type        = list(map(string))
  default     = []
}

variable "instance_refresh" {
  description = "If this block is configured, start an Instance Refresh when this Auto Scaling Group is updated"
  type        = any
  default     = {}
}

variable "asg_tags_propagate_at_launch" {
  description = "Propagate AutoScaling group tags to the launched EC2 instances"
  type        = bool
  default     = true
}

variable "asg_tags" {
  description = "Add additional tags to the AutoScaling group. Also for this module asg_tags will be used with provider as well"
  type        = map(string)
  default     = {}
}

variable "min_elb_capacity" {
  description = "Setting this causes Terraform to wait for this number of Instances from this Auto Scaling Group to show up healthy in the ELB only on creation"
  type        = number
  default     = 0
}

variable "wait_for_elb_capacity" {
  description = "Setting this will cause Terraform to wait for exactly this number of healthy Instances from this Auto Scaling Group in all attached load balancers on both create and update operations"
  type        = number
  default     = 0
}

variable "wait_for_capacity_timeout" {
  description = "Maximum duration that Terraform should wait for ASG instances to be healthy before timing out."
  type        = string
  default     = "10m"
}

##############################
# Autoscaling policy variables
##############################

variable "scaling_policies" {
  description = "Map of target scaling policy schedule to create"
  type        = any
  default     = {}
}

variable "region" {
  description = "Optional AWS Region for regional resources. If null, resources use the configured provider region."
  type        = string
  default     = null

  validation {
    condition = (
      var.region == null ||
      contains(["us-east-1", "us-east-2"], var.region)
    )
    error_message = "Region must be null, 'us-east-1', or 'us-east-2'."
  }
}
