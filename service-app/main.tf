variable "namespace" {}
variable "stack" {}
variable "cluster" {}
variable "service" { default = "app" }
variable "aws_route53_name" { default = "app" }
variable "aws_region" {}
variable "vpc_id" {}
variable "subnet_a_id" {}
variable "subnet_b_id" {}
variable "subnet_public_a_id" {}
variable "subnet_public_b_id" {}
variable "aws_ssl_arn" {}
variable "aws_root_zone_id" {}
variable "sg_base_id" {}
variable "iam_role_arn" {}
variable "iam_profile" {}
variable "aws_instance_type" {}
variable "db_instance_type" {}
variable "aws_key_name" {}
variable "ami" {}
variable "db" {}
variable "app_conf" {}

variable "app_internal" {}
variable "db_name" {}
variable "db_username" {}
variable "db_password" {}
variable "db_version" {}
variable "db_family" {}
variable "db_storage" {}
variable "db_storage_iops" {}
variable "db_storage_type" {}
variable "web_container" {}
variable "web_container_port" {}
variable "web_container_expose" {}
variable "capacity_min" {}
variable "capacity_max" {}
variable "capacity_desired" {}

module "app-s3" {
  source = "../../modules/service-s3-backup"
  namespace = "${var.namespace}"
  stack = "${var.stack}"
  cluster = "${var.cluster}"
  service = "${var.service}"
}

module "cluster-app" {
  source = "../../modules/cluster"
  stack = "${var.stack}"
  cluster = "${var.cluster}"
  vpc_id = "${var.vpc_id}"
  subnet_a_id = "${var.subnet_a_id}"
  subnet_b_id = "${var.subnet_b_id}"
  min_size = "${var.capacity_min}"
  max_size = "${var.capacity_max}"
  desired_capacity = "${var.capacity_desired}"
  aws_image_id = "${var.ami}"
  aws_instance_type = "${var.aws_instance_type}"
  aws_key_name = "${var.aws_key_name}"
  iam_instance_profile_id = "${var.iam_profile}"
  sg_base_id = "${var.sg_base_id}"
}

module "cluster-db" {
  source = "../../modules/service-rds-postgres"
  stack = "${var.stack}"
  cluster = "${var.cluster}"
  service = "${var.service}"
  vpc_id = "${var.vpc_id}"
  subnet_a_id = "${var.subnet_a_id}"
  subnet_b_id = "${var.subnet_b_id}"
  db_instance_type = "${var.db_instance_type}"
  cluster_sg_id = "${module.cluster-app.sg_cluster_id}"
  db = "${var.db}"
  app_conf = "${var.app_conf}"
  db_name = "${var.db_name}"
  db_username = "${var.db_username}"
  db_password = "${var.db_password}"
  db_version = "${var.db_version}"
  db_family = "${var.db_family}"
  db_storage = "${var.db_storage}"
  db_storage_iops = "${var.db_storage_iops}"
  db_storage_type = "${var.db_storage_type}"
}

resource "template_file" "task" {
  template = "${file("tasks/${var.service}.json")}"

  vars {
    s3bucket = "${var.namespace}-${var.stack}-${var.cluster}-${var.service}"
    aws_id = "${module.app-s3.aws_id}"
    aws_secret = "${module.app-s3.aws_secret}"
    stack = "${var.stack}"
    cluster = "${var.cluster}"
    service = "${var.service}"
    aws_region = "${var.aws_region}"
    app_conf = "${var.app_conf}"
    db_url = "${module.cluster-db.app-db-endpoint}"
  }
}

resource "aws_ecs_task_definition" "app" {
  family = "${var.stack}-${var.cluster}"
  container_definitions = "${template_file.task.rendered}"

  volume {
    name = "${var.stack}"
    host_path = "/ecs/${var.stack}"
  }
  volume {
    name = "backup"
    host_path = "/ecs/${var.stack}"
  }
}

/* ELB for the service */
resource "aws_elb" "service" {
  name  = "${var.stack}-${var.cluster}-${var.service}-elb"
  subnets = [
    "${var.subnet_public_a_id}",
    "${var.subnet_public_b_id}"
  ]

  security_groups = [
    "${aws_security_group.elb-sg.id}",
    "${var.sg_base_id}"
  ]

  listener {
    lb_port            = 80
    lb_protocol        = "http"
    instance_port      = "${var.web_container_expose}"
    instance_protocol  = "http"
  }

  listener {
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "${var.aws_ssl_arn}"
    instance_port      = "${var.web_container_expose}"
    instance_protocol  = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 30
    target              = "TCP:${var.web_container_expose}"
    interval            = 60
  }

  connection_draining = false
  cross_zone_load_balancing = true
  internal = "${var.app_internal}"

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
}

# extending service-default sg with service rule
# enable service cluster to receive traffic from service ELB
resource "aws_security_group_rule" "service-http-ingress" {
  type = "ingress"
  from_port = "${var.web_container_expose}"
  to_port = "${var.web_container_expose}"
  protocol = "tcp"

  security_group_id = "${module.cluster-app.sg_cluster_id}"
  source_security_group_id = "${aws_security_group.elb-sg.id}"
}

module "app_zone" {
  source = "../../modules/service-dns-zone"
  aws_zone = "${var.aws_route53_name}"
  aws_root_zone_id = "${var.aws_root_zone_id}"
}

resource "aws_route53_record" "service-elb" {
  zone_id = "${module.app_zone.zone_id}"
  name = "${var.aws_route53_name}"
  type = "A"

  alias {
    name = "${aws_elb.service.dns_name}"
    zone_id = "${aws_elb.service.zone_id}"
    evaluate_target_health = false
  }
}

# below ensures that we expose HTTPS
# we still need to ensure SSH is exposed to ELB
resource "aws_ecs_service" "service" {
  name = "${var.stack}-${var.cluster}-${var.service}"
  cluster = "${module.cluster-app.cluster_id}"

  task_definition = "${aws_ecs_task_definition.app.arn}"
  desired_count = "${var.capacity_desired}"

  iam_role = "${var.iam_role_arn}"

  deployment_maximum_percent = 100
  deployment_minimum_healthy_percent = 50

  load_balancer {
    elb_name = "${aws_elb.service.id}"
    container_name = "${var.web_container}"
    container_port = "${var.web_container_port}"
  }
}
