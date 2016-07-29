variable "stack" {}
variable "cluster" {}
variable "service" {}
variable "vpc_id" {}
variable "subnet_a_id" {}
variable "subnet_b_id" {}
variable "cluster_sg_id" {}
variable "db_instance_type" {}
variable "db" {}
variable "app_conf" {}
variable "db_name" {}
variable "db_username" {}
variable "db_password" {}
variable "db_version" {}
variable "db_family" {}
variable "db_storage" {}
variable "db_storage_iops" {}
variable "db_storage_type" {}

resource "aws_db_instance" "app-db" {
  # count = "${element(split(",", var.db), index(split(",", var.db), enabled) + 1)}"
  identifier = "${var.stack}-${var.service}-db"
  allocated_storage = "${var.db_storage}"
  storage_type = "${var.db_storage_type}"
  iops = "${var.db_storage_iops}"
  engine = "postgres"
  engine_version = "${var.db_version}"
  instance_class = "${var.db_instance_type}"
  name = "${var.db_name}"
  username = "${var.db_username}"
  password = "${var.db_password}"
  parameter_group_name = "${aws_db_parameter_group.default-params.name}"
  db_subnet_group_name = "${aws_db_subnet_group.default-db-subnet.id}"
  vpc_security_group_ids = ["${aws_security_group.default-db-sg.id}"]
  backup_retention_period = "30"
  multi_az = true
  publicly_accessible = false
  auto_minor_version_upgrade = true
  apply_immediately = true

  tags = {
    Name = "${var.stack}-${var.service}-db"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "default-params" {
    name = "${var.stack}-${var.service}-params"
    family = "${var.db_family}"
    description = "RDS default parameter group for ${var.stack}-${var.service}"

    parameter {
      name = "rds.force_ssl"
      value = "1"
      apply_method = "pending-reboot"
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
}

resource "aws_db_subnet_group" "default-db-subnet" {
    name = "${var.stack}-${var.service}-subnet"
    description = "${var.stack}-${var.service}-subnet"
    subnet_ids = ["${var.subnet_a_id}", "${var.subnet_b_id}"]
}

output "app-db-endpoint" {
  value = "postgres://${var.db_username}:${var.db_password}@${aws_db_instance.app-db.endpoint}/${var.db_name}?sslmode=require"
}
