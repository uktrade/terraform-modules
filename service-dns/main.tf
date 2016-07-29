variable "aws_zone_id" {}
variable "aws_route53_name" {}
variable "aws_route53_type" {}
variable "aws_route53_record" {}

resource "aws_route53_record" "public" {
  zone_id = "${var.aws_zone_id}"
  name = "${var.aws_route53_name}"
  type = "${var.aws_route53_type}"
  ttl = "30"
  records = "${var.aws_route53_record}"
}

output "fqdn" {
  value = "${aws_route53_record.public.fqdn}"
}
