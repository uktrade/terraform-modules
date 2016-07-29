variable "namespace" {}
variable "stack" {}
variable "cluster" {}
variable "service" {}


resource "aws_s3_bucket" "backup" {
    bucket = "${var.namespace}-${var.stack}-${var.cluster}-${var.service}"
    acl = "private"

    tags {
      Stack = "${var.stack}"
      Name = "Backup bucket"
    }
}

resource "template_file" "backup-policy" {
  template = "${file("${path.module}/service-backup-policy.tpl")}"

  vars {
    s3bucket = "${var.namespace}-${var.stack}-${var.cluster}-${var.service}"
  }
}

resource "aws_iam_user" "backup" {
    name = "${var.cluster}-${var.service}-backup"
    path = "/${var.namespace}/${var.stack}/"
}

resource "aws_iam_access_key" "backup" {
    user = "${aws_iam_user.backup.name}"
}

resource "aws_iam_user_policy" "backup" {
    name = "${var.cluster}-${var.service}-backup"
    user = "${aws_iam_user.backup.name}"
    policy = "${template_file.backup-policy.rendered}"
}


output "aws_id" {
  value = "${aws_iam_access_key.backup.id}"
}

output "aws_secret" {
  value = "${aws_iam_access_key.backup.secret}"
}
