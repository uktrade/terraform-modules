variable "stack" {}
variable "cluster" {}
variable "service" {}
variable "vpc_conf" { type = "map" }
variable "db" { type = "map" }
variable "app_conf" { type = "map" }

variable "rds_param" {}
variable "rds_subnet" {}
variable "rds_sg" {}

resource "aws_db_instance" "app-db" {
  count = "${var.app_conf["db_enabled"]}"
  identifier = "${var.stack}-${var.service}-db"
  engine = "postgres"

  allocated_storage = "${var.db["storage"]}"
  storage_type = "${var.db["storage_type"]}"
  engine_version = "${var.db["version"]}"
  instance_class = "${var.db["instance_type"]}"
  name = "${var.app_conf["db_name"]}"
  username = "${var.app_conf["db_username"]}"
  password = "${var.app_conf["db_password"]}"

  parameter_group_name = "${var.rds_param}"
  db_subnet_group_name = "${rds_subnet}"
  vpc_security_group_ids = ["${rds_sg}"]
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

output "db_conf" {
  value = "${map(
    "host", "${aws_db_instance.app-db.address}",
    "port", "${aws_db_instance.app-db.port}",
    "url", "postgres://${var.app_conf["db_username"]}:${var.app_conf["db_password"]}@${aws_db_instance.app-db.endpoint}/${var.app_conf["db_name"]}?sslmode=require"
  )}"
}
