variable "namespace" {}
variable "stack" {}
variable "cluster" {}
variable "service" { default = "app" }
variable "aws_region" {}
variable "vpc_conf" { type = "map" }
variable "cluster_conf" { type = "map" }
variable "aws_root_zone_id" {}
variable "iam_role_arn" {}
variable "iam_profile" {}
variable "aws_instance_type" {}
variable "aws_key_name" {}
variable "ami" {}
variable "db" { type = "map" }
variable "app_conf" { type = "map" }

variable "vpc_id" {}
variable "subnets_public_a" {}
variable "subnets_public_b" {}
variable "subnets_public_c" {}
variable "subnets_private_a" {}
variable "subnets_private_b" {}
variable "subnets_private_c" {}
variable "vpc_security_group" {}

module "app-s3" {
  source = "../../modules/service-s3-backup"
  namespace = "${var.namespace}"
  stack = "${var.stack}"
  cluster = "${var.cluster}"
  service = "${var.service}"
}

module "cluster-db" {
  source = "../../modules/service-rds-postgres"
  stack = "${var.stack}"
  cluster = "${var.cluster}"
  service = "${var.service}"
  vpc_conf = "${var.vpc_conf}"
  cluster_sg_id = "${var.cluster_conf["id"]}"
  db = "${var.db}"
  app_conf = "${var.app_conf}"

  vpc_id = "${var.vpc_id}"
  subnets_public_a = "${var.subnets_public_a}"
  subnets_public_b = "${var.subnets_public_b}"
  subnets_public_c = "${var.subnets_public_c}"
  subnets_private_a = "${var.subnets_private_a}"
  subnets_private_b = "${var.subnets_private_b}"
  subnets_private_c = "${var.subnets_private_c}"

  db_version = "${var.db["version"]}"
  db_family = "${var.db["family"]}"
  db_storage = "${var.db["storage"]}"
  db_storage_iops = "${var.db["iops"]}"
  db_storage_type = "${var.db["storage_type"]}"
  db_instance_type = "${var.db["instance_type"]}"
  db_name = "${var.app_conf["db_name"]}"
  db_username = "${var.app_conf["db_username"]}"
  db_password = "${var.app_conf["db_password"]}"
}

data "template_file" "task" {
  template = "${file("tasks/${var.service}.json")}"

  vars {
    s3bucket = "${var.namespace}-${var.stack}-${var.cluster}-${var.service}"
    aws_id = "${module.app-s3.aws_id}"
    aws_secret = "${module.app-s3.aws_secret}"
    stack = "${var.stack}"
    cluster = "${var.cluster}"
    service = "${var.service}"
    aws_region = "${var.aws_region}"
    db_url = "${module.cluster-db.app_db_endpoint}"
  }
}

resource "aws_ecs_task_definition" "app" {
  family = "${var.stack}-${var.cluster}"
  container_definitions = "${data.template_file.task.rendered}"

  volume {
    name = "${var.stack}"
    host_path = "/ecs/${var.stack}"
  }
  volume {
    name = "backup"
    host_path = "/ecs/${var.stack}"
  }
}

resource "aws_elb" "service" {
  name  = "${var.stack}-${var.cluster}-${var.service}-elb"
  # subnets = ["${lookup(var.vpc_conf["subnets"], "public")}"]
  subnets = ["${var.subnets_public_a}", "${var.subnets_public_b}", "${var.subnets_public_c}"]

  security_groups = [
    "${aws_security_group.elb-sg.id}",
    "${var.vpc_security_group}"
  ]

  listener {
    lb_port            = 80
    lb_protocol        = "http"
    instance_port      = "${var.app_conf["web_container_expose"]}"
    instance_protocol  = "http"
  }

  listener {
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "${var.app_conf["aws_ssl_arn"]}"
    instance_port      = "${var.app_conf["web_container_expose"]}"
    instance_protocol  = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 30
    target              = "TCP:${var.app_conf["web_container_expose"]}"
    interval            = 60
  }

  connection_draining = false
  cross_zone_load_balancing = true
  internal = "${var.app_conf["internal"]}"

  tags {
    Stack = "${var.stack}"
    Name = "${var.service}-elb"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "elb-sg" {
  name = "${var.stack}-${var.cluster}-${var.service}-elb"
  description = "ELB Incoming traffic"

  vpc_id = "${var.vpc_id}"

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "elb-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "service-http-ingress" {
  type = "ingress"
  from_port = "${var.app_conf["web_container_expose"]}"
  to_port = "${var.app_conf["web_container_expose"]}"
  protocol = "tcp"

  security_group_id = "${var.cluster_conf["security_group"]}"
  source_security_group_id = "${aws_security_group.elb-sg.id}"
}

module "app_zone" {
  source = "../../modules/service-dns-zone"
  aws_zone = "${var.app_conf["aws_route53_name"]}"
  aws_root_zone_id = "${var.aws_root_zone_id}"
}

resource "aws_route53_record" "service-elb" {
  zone_id = "${module.app_zone.zone_id}"
  name = "${var.app_conf["aws_route53_name"]}"
  type = "A"

  alias {
    name = "${aws_elb.service.dns_name}"
    zone_id = "${aws_elb.service.zone_id}"
    evaluate_target_health = false
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_ecs_service" "service" {
  name = "${var.stack}-${var.cluster}-${var.service}"
  cluster = "${var.cluster_conf["id"]}"

  task_definition = "${aws_ecs_task_definition.app.arn}"
  desired_count = "${var.app_conf["capacity_desired"]}"

  iam_role = "${var.iam_role_arn}"

  deployment_maximum_percent = 100
  deployment_minimum_healthy_percent = 50

  load_balancer {
    elb_name = "${aws_elb.service.id}"
    container_name = "${var.app_conf["web_container"]}"
    container_port = "${var.app_conf["web_container_port"]}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_appautoscaling_target" "autoscale-service" {
  service_namespace = "ecs"
  resource_id = "service/${var.stack}-${var.cluster}/${var.stack}-${var.cluster}-${var.service}"
  scalable_dimension = "ecs:service:DesiredCount"
  role_arn = "${var.iam_role_arn}"
  min_capacity = "${var.app_conf["capacity_min"]}"
  max_capacity = "${var.app_conf["capacity_max"]}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_appautoscaling_policy" "autoscale-policy-service" {
  name = "${var.stack}-${var.cluster}-${var.service}"
  service_namespace = "ecs"
  resource_id = "service/${var.stack}-${var.cluster}/${var.stack}-${var.cluster}-${var.service}"
  scalable_dimension = "ecs:service:DesiredCount"
  adjustment_type = "ChangeInCapacity"
  cooldown = 3600
  metric_aggregation_type = "Maximum"
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
  depends_on = ["aws_appautoscaling_target.autoscale-service"]

  lifecycle {
    create_before_destroy = true
  }
}
