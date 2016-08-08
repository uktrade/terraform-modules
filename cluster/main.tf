variable "stack" {}
variable "cluster" {}
variable "vpc_conf" { type = "map" }
variable "desired_capacity" { default = 1 }
variable "aws_image_id" {}
variable "aws_instance_type" {}
variable "aws_key_name" {}
variable "iam_instance_profile_id" {}
variable "app_conf" { type = "map" }

variable "vpc_id" {}
variable "subnets_public_a" {}
variable "subnets_public_b" {}
variable "subnets_public_c" {}
variable "subnets_private_a" {}
variable "subnets_private_b" {}
variable "subnets_private_c" {}
variable "vpc_security_group" {}

resource "aws_ecs_cluster" "cluster" {
  name = "${var.stack}-${var.cluster}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "cluster-sg" {
  name = "${var.stack}-${var.cluster}"
  description = "Service ${var.cluster}"

  vpc_id = "${var.vpc_id}"

  tags {
    Name = "${var.cluster}"
    Stack = "${var.stack}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_configuration" "cluster" {
  name_prefix  = "${var.stack}-${var.cluster}-"
  image_id  = "${var.aws_image_id}"

  instance_type = "${var.aws_instance_type}"
  key_name = "${var.aws_key_name}"
  iam_instance_profile = "${var.iam_instance_profile_id}"
  security_groups = [
    "${var.vpc_security_group}",
    "${aws_security_group.cluster-sg.id}"
  ]
  user_data = "#!/bin/bash\necho ECS_CLUSTER=${aws_ecs_cluster.cluster.name} > /etc/ecs/ecs.config"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "cluster" {
  name                 = "${var.stack}-${var.cluster}"
  launch_configuration = "${aws_launch_configuration.cluster.name}"

  vpc_zone_identifier = ["${var.subnets_private_a}", "${var.subnets_private_b}", "${var.subnets_private_c}"]

  tag {
    key = "Name"
    value = "${var.stack}-${var.cluster}-asg-node"
    propagate_at_launch = true
  }

  tag {
    key = "Stack"
    value = "${var.stack}"
    propagate_at_launch = true
  }

  min_size             = "${var.app_conf["capacity_min"]}"
  max_size             = "${var.app_conf["capacity_max"]}"
  desired_capacity     = "${var.app_conf["capacity_desired"]}"

  # as "Terraform v0.6.14" failed to identify that ASG was in place
  wait_for_capacity_timeout = 0

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "cluster-autoscale" {
  name = "${var.stack}-${var.cluster}-scale-policy"
  autoscaling_group_name = "${aws_autoscaling_group.cluster.name}"
  adjustment_type = "ChangeInCapacity"
  metric_aggregation_type = "Maximum"
  policy_type = "StepScaling"
  step_adjustment {
    metric_interval_lower_bound = 3.0
    scaling_adjustment = 2
  }
  step_adjustment {
    metric_interval_lower_bound = 2.0
    metric_interval_upper_bound = 3.0
    scaling_adjustment = 2
  }
  step_adjustment {
    metric_interval_lower_bound = 1.0
    metric_interval_upper_bound = 2.0
    scaling_adjustment = -1
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "ecs-logs" {
  name = "${var.stack}-${var.cluster}"

  lifecycle {
    create_before_destroy = true
  }
}

output "sg_cluster_id" {
  value = "${aws_security_group.cluster-sg.id}"
}

output "cluster_id" {
  value = "${aws_ecs_cluster.cluster.id}"
}
