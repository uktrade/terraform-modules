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
variable "subnets_a" {}
variable "subnets_b" {}
variable "subnets_c" {}
variable "vpc_security_group" {}

resource "aws_ecs_cluster" "cluster" {
  name = "${var.stack}-${var.cluster}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_efs_file_system" "cluster-efs" {
  tags {
    Name = "${var.stack}-${var.cluster}"
  }
}

resource "aws_security_group" "cluster-efs" {
  name = "${var.stack}-${var.cluster}-efs"
  description = "Service ${var.cluster}"

  vpc_id = "${var.vpc_id}"

  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    security_groups = ["${aws_security_group.cluster-sg.id}"]
  }

  tags {
    Name = "${var.cluster}"
    Stack = "${var.stack}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_efs_mount_target" "cluster-efs-a" {
  file_system_id = "${aws_efs_file_system.cluster-efs.id}"
  subnet_id = "${var.subnets_a}"
  security_groups = ["${aws_security_group.cluster-efs.id}"]
}

resource "aws_efs_mount_target" "cluster-efs-b" {
  file_system_id = "${aws_efs_file_system.cluster-efs.id}"
  subnet_id = "${var.subnets_b}"
  security_groups = ["${aws_security_group.cluster-efs.id}"]
}

resource "aws_efs_mount_target" "cluster-efs-c" {
  file_system_id = "${aws_efs_file_system.cluster-efs.id}"
  subnet_id = "${var.subnets_c}"
  security_groups = ["${aws_security_group.cluster-efs.id}"]
}

data "template_file" "cloudinit" {
  template = "${file("./modules/cluster/cloud-init.conf")}"

  vars {
    efs_id = "${aws_efs_file_system.cluster-efs.id}"
    cluster_name = "${aws_ecs_cluster.cluster.name}"
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
  user_data = "${data.template_file.cloudinit.rendered}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "cluster" {
  name                 = "${var.stack}-${var.cluster}"
  launch_configuration = "${aws_launch_configuration.cluster.name}"

  vpc_zone_identifier = ["${var.subnets_a}", "${var.subnets_b}", "${var.subnets_c}"]

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

data "null_data_source" "cluster_conf" {
  inputs = {
    id = "${aws_ecs_cluster.cluster.id}"
    security_group = "${aws_security_group.cluster-sg.id}"
  }
}

output "cluster_conf" {
  value = "${data.null_data_source.cluster_conf.input}"
}

output "sg_cluster_id" {
  value = "${aws_security_group.cluster-sg.id}"
}

output "cluster_id" {
  value = "${aws_ecs_cluster.cluster.id}"
}
