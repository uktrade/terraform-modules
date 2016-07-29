variable "stack" {}
variable "cluster" {}
variable "vpc_id" {}
variable "subnet_a_id" {}
variable "subnet_b_id" {}
variable "min_size" { default = 1 }
variable "max_size" { default = 10 }
variable "desired_capacity" { default = 1 }
variable "aws_image_id" {}
variable "aws_instance_type" {}
variable "aws_key_name" {}
variable "iam_instance_profile_id" {}
variable "sg_base_id" {}

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
    "${var.sg_base_id}",
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

  vpc_zone_identifier = [
    "${var.subnet_a_id}",
    "${var.subnet_b_id}"
  ]

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

  min_size             = "${var.min_size}"
  max_size             = "${var.max_size}"
  desired_capacity     = "${var.desired_capacity}"

  # as "Terraform v0.6.14" failed to identify that ASG was in place
  wait_for_capacity_timeout = 0
}

resource "aws_cloudwatch_log_group" "ecs-logs" {
  name = "${var.stack}-${var.cluster}"
}


output "sg_cluster_id" {
  value = "${aws_security_group.cluster-sg.id}"
}

output "cluster_id" {
  value = "${aws_ecs_cluster.cluster.id}"
}
