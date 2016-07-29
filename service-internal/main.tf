variable "stack" {}
variable "cluster" {}
variable "service" {}
variable "aws_route53_name" {}

variable "aws_region" {}
variable "vpc_id" {}
variable "subnet_a_id" {}
variable "subnet_b_id" {}
variable "sg_base_id" {}
variable "aws_ssl_arn" {}

variable "container_port" {}
variable "container_name" {}

variable "instance_port" { default = 443 }
variable "instance_protocol" { default = "https" }
variable "health_check_target" { default = "HTTPS:443" }

variable "sg_cluster_id" {}

variable "aws_route53_zone_id" {}

variable "cluster_id" {}

variable "task_definition_arn" {}
variable "iam_role_arn" {}
variable "task_desired_count" { default = 1 }


/* ELB for the service */
resource "aws_elb" "service" {
  name  = "${var.stack}-${var.cluster}-${var.service}-elb"
  subnets = [
    "${var.subnet_a_id}",
    "${var.subnet_b_id}"
  ]

  security_groups = [
    "${aws_security_group.elb-sg.id}",
    "${var.sg_base_id}"
  ]

  listener {
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "${var.aws_ssl_arn}"
    instance_port      = "${var.instance_port}"
    instance_protocol  = "${var.instance_protocol}"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 30
    target              = "${var.health_check_target}"
    interval            = 60
  }

  connection_draining = false
  cross_zone_load_balancing = true
  internal = true

  tags {
    Stack = "${var.stack}"
    Name = "${var.service}-elb"
  }
}


resource "aws_security_group" "elb-sg" {
  name = "${var.stack}-${var.cluster}-${var.service}-elb"
  description = "ELB Incoming traffic"

  vpc_id = "${var.vpc_id}"

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    security_groups = ["${var.sg_base_id}"]
  }

  tags {
    Name = "elb-sg"
  }
}



# extending service-default sg with service rule
# enable service cluster to receive traffic from service ELB
resource "aws_security_group_rule" "service-ingress" {
  type = "ingress"
  from_port = "${var.instance_port}"
  to_port = "${var.instance_port}"
  protocol = "tcp"

  security_group_id = "${var.sg_cluster_id}"
  source_security_group_id = "${aws_security_group.elb-sg.id}"
}


resource "aws_route53_record" "service-elb" {
  zone_id = "${var.aws_route53_zone_id}"
  name = "${var.aws_route53_name}"
  type = "A"

  alias {
    name = "${aws_elb.service.dns_name}"
    zone_id = "${aws_elb.service.zone_id}"
    evaluate_target_health = false
  }
}


resource "aws_ecs_service" "service" {
  name = "${var.stack}-${var.cluster}-${var.service}"
  cluster = "${var.cluster_id}"

  task_definition = "${var.task_definition_arn}"
  desired_count = "${var.task_desired_count}"

  iam_role = "${var.iam_role_arn}"

  deployment_minimum_healthy_percent = 0

  load_balancer {
    elb_name = "${aws_elb.service.id}"
    container_name = "${var.container_name}"
    container_port = "${var.container_port}"
  }
}
