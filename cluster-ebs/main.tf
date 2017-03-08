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

data "aws_region" "region" {
  current = true
}

resource "aws_ebs_volume" "cluster_ebs" {
  availability_zone = "${data.aws_region.region.name}"
  size = 200
  type = "gp2"
  tags {
    Name = "${aws_ecs_cluster.cluster.name}"
  }
  lifecycle {
    prevent_destroy = true
    ignore_changes = ["*"]
  }
}

data "template_file" "cloudinit" {
  template = "${file("./modules/cluster-ebs/cloudinit.yml")}"

  vars {
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

resource "aws_instance" "cluster_instance" {
  ami  = "${var.aws_image_id}"
  instance_type = "${var.aws_instance_type}"
  subnet_id = "${var.subnets_a}"
  key_name = "${var.aws_key_name}"
  iam_instance_profile = "${var.iam_instance_profile_id}"
  associate_public_ip_address = false
  source_dest_check = true
  root_block_device {
    volume_type = "gp2"
    volume_size = 40
  }
  vpc_security_group_ids = [
    "${var.vpc_security_group}",
    "${aws_security_group.cluster-sg.id}"
  ]
  user_data = "${data.template_file.cloudinit.rendered}"

  tags {
    Name = "${var.stack}-${var.cluster}-node"
    Stack = "${var.stack}-${var.cluster}"
  }
}

resource "aws_volume_attachment" "instance_ebs" {
  device_name = "/dev/sdh"
  volume_id = "${aws_ebs_volume.cluster_ebs.id}"
  instance_id = "${aws_instance.cluster_instance.id}"
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

output "cluster_instance" {
  value = "${aws_instance.cluster_instance.id}"
}
