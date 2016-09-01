variable "aws_zone" {}
variable "aws_root_zone_id" {}

resource "aws_route53_zone" "app_zone" {
  name = "${var.aws_zone}"
}

/*
 * Disabled, Terraform bug
resource "aws_route53_record" "zone_dns" {
  zone_id = "${var.aws_root_zone_id}"
  name = "${var.aws_zone}"
  type = "NS"
  ttl = "30"
  records = [
    "${aws_route53_zone.app_zone.name_servers.0}",
    "${aws_route53_zone.app_zone.name_servers.1}",
    "${aws_route53_zone.app_zone.name_servers.2}",
    "${aws_route53_zone.app_zone.name_servers.3}"
  ]
}
*/

output "zone_id" {
  value = "${aws_route53_zone.app_zone.zone_id}"
}
