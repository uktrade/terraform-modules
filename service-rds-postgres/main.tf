variable "stack" {}
variable "cluster" {}
variable "service" {}
variable "vpc_id" {}
variable "subnet_a_id" {}
variable "subnet_b_id" {}
variable "cluster_sg_id" {}
variable "db" { type = "map" }
variable "app_conf" { type = "map" }


resource "aws_db_instance" "app-db" {
  # count = "${element(split(",", var.db), index(split(",", var.db), enabled) + 1)}"
  identifier = "${var.stack}-${var.service}-db"
  allocated_storage = "${var.db["storage"]}"
  storage_type = "${var.db["storage_type"]}"
  iops = "${var.db["iops"]}"
  engine = "postgres"
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

output "app_db_endpoint" {
  value = "postgres://${var.app_conf["db_username"]}:${var.app_conf["db_password"]}@${aws_db_instance.app-db.endpoint}/${var.app_conf["db_name"]}?sslmode=require"
}
