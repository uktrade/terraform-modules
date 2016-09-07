variable "stack" {}
variable "cluster" {}
variable "service" {}
variable "vpc_conf" { type = "map" }
variable "cluster_sg_id" {}
variable "db" { type = "map" }
variable "app_conf" { type = "map" }

variable "vpc_id" {}
variable "subnets_public_a" {}
variable "subnets_public_b" {}
variable "subnets_public_c" {}
variable "subnets_private_a" {}
variable "subnets_private_b" {}
variable "subnets_private_c" {}

variable "iops_enabled" {
  type = "map"
  default = {
    gp2 = "-1"
    io1 = "1"
  }
}
variable "iops_disabled" {
  type = "map"
  default = {
    gp2 = "1"
    io1 = "-1"
  }
}

resource "aws_db_instance" "app-db" {
  count = "${signum(lookup(var.iops_disabled, var.db["storage_type"]) + var.app_conf["db_enabled"])}"
  identifier = "${var.stack}-${var.service}-db"
  engine = "postgres"

  allocated_storage = "${var.db["storage"]}"
  storage_type = "${var.db["storage_type"]}"
  engine_version = "${var.db["version"]}"
  instance_class = "${var.db["instance_type"]}"
  name = "${var.app_conf["db_name"]}"
  username = "${var.app_conf["db_username"]}"
  password = "${var.app_conf["db_password"]}"

  parameter_group_name = "${aws_db_parameter_group.default-params.name}"
  db_subnet_group_name = "${aws_db_subnet_group.default-db-subnet.id}"
  vpc_security_group_ids = ["${aws_security_group.default-db-sg.id}"]
  backup_retention_period = "30"
  multi_az = false
  publicly_accessible = false
  auto_minor_version_upgrade = true
  apply_immediately = true
  skip_final_snapshot = false

  tags = {
    Name = "${var.stack}-${var.service}-db"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "app-db-iops" {
  count = "${signum(lookup(var.iops_enabled, var.db["storage_type"]) + var.app_conf["db_enabled"])}"
  identifier = "${var.stack}-${var.service}-db"
  engine = "postgres"

  allocated_storage = "${var.db["storage"]}"
  storage_type = "${var.db["storage_type"]}"
  iops = "${var.db["iops"]}"
  engine_version = "${var.db["version"]}"
  instance_class = "${var.db["instance_type"]}"
  name = "${var.app_conf["db_name"]}"
  username = "${var.app_conf["db_username"]}"
  password = "${var.app_conf["db_password"]}"

  parameter_group_name = "${aws_db_parameter_group.default-params.name}"
  db_subnet_group_name = "${aws_db_subnet_group.default-db-subnet.id}"
  vpc_security_group_ids = ["${aws_security_group.default-db-sg.id}"]
  backup_retention_period = "30"
  multi_az = true
  publicly_accessible = false
  auto_minor_version_upgrade = true
  apply_immediately = true
  skip_final_snapshot = false

  tags = {
    Name = "${var.stack}-${var.service}-db"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "default-params" {
    name = "${var.stack}-${var.service}-params"
    family = "${var.db["family"]}"
    description = "RDS default parameter group for ${var.stack}-${var.service}"

    parameter {
      name = "rds.force_ssl"
      value = "1"
      apply_method = "pending-reboot"
    }

    lifecycle {
      create_before_destroy = true
    }
}

resource "aws_security_group" "default-db-sg" {
  name = "${var.stack}-${var.service}-sg"
  vpc_id = "${var.vpc_id}"

  ingress {
    from_port = 5432
    to_port = 5432
    protocol = "TCP"
    security_groups = ["${var.cluster_sg_id}"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${var.stack}-${var.service}-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_subnet_group" "default-db-subnet" {
    name = "${var.stack}-${var.service}-subnet"
    description = "${var.stack}-${var.service}-subnet"
    # subnet_ids = ["${lookup(var.vpc_conf["subnets"], "private")}"]
    subnet_ids = ["${var.subnets_private_a}", "${var.subnets_private_b}", "${var.subnets_private_c}"]

    lifecycle {
      create_before_destroy = true
    }
}

data "null_data_source" "db_conf" {
  inputs = {
    host = "${aws_db_instance.app-db.address}"
    url = "postgres://${var.app_conf["db_username"]}:${var.app_conf["db_password"]}@${aws_db_instance.app-db.endpoint}/${var.app_conf["db_name"]}?sslmode=require"
  }
}

output "db_conf" {
  value = "${data.null_data_source.db_conf.input}"
}


output "db_host" {
  value = "${aws_db_instance.app-db.address}"
}

output "db_port" {
  value = "${aws_db_instance.app-db.port}"
}

output "db_url" {
  value = "postgres://${var.app_conf["db_username"]}:${var.app_conf["db_password"]}@${aws_db_instance.app-db.endpoint}/${var.app_conf["db_name"]}?sslmode=require"
}
