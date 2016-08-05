variable "stack" {}
variable "aws_region" {}
variable "aws_root_zone" {}

# VPC
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags {
    Stack = "${var.stack}"
    Name = "default"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_internet_gateway" "default" {
    vpc_id = "${aws_vpc.default.id}"
}


# Public Subnets
resource "aws_subnet" "public-1a" {
  vpc_id = "${aws_vpc.default.id}"

  cidr_block = "10.0.0.0/24"
  availability_zone = "eu-west-1a"

  tags {
    Stack = "${var.stack}"
    Name = "Public Subnet"
  }
}

resource "aws_subnet" "public-1b" {
  vpc_id = "${aws_vpc.default.id}"

  cidr_block = "10.0.1.0/24"
  availability_zone = "eu-west-1b"

  tags {
    Stack = "${var.stack}"
    Name = "Public Subnet"
  }
}

resource "aws_subnet" "public-1c" {
  vpc_id = "${aws_vpc.default.id}"

  cidr_block = "10.0.2.0/24"
  availability_zone = "eu-west-1c"

  tags {
    Stack = "${var.stack}"
    Name = "Public Subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.default.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.default.id}"
  }

  tags {
    Stack = "${var.stack}"
    Name = "Public routing"
  }
}

resource "aws_route_table_association" "public-1a" {
  subnet_id = "${aws_subnet.public-1a.id}"
  route_table_id = "${aws_route_table.public.id}"
}

resource "aws_route_table_association" "public-1b" {
  subnet_id = "${aws_subnet.public-1b.id}"
  route_table_id = "${aws_route_table.public.id}"
}

resource "aws_route_table_association" "public-1c" {
  subnet_id = "${aws_subnet.public-1c.id}"
  route_table_id = "${aws_route_table.public.id}"
}


# Private Subnets
resource "aws_subnet" "private-1a" {
  vpc_id = "${aws_vpc.default.id}"

  cidr_block = "10.0.4.0/24"
  availability_zone = "eu-west-1a"

  tags {
    Stack = "${var.stack}"
    Name = "Private Subnet 1a"
  }
}

resource "aws_subnet" "private-1b" {
  vpc_id = "${aws_vpc.default.id}"

  cidr_block = "10.0.5.0/24"
  availability_zone = "eu-west-1b"

  tags {
    Stack = "${var.stack}"
    Name = "Private Subnet 1b"
  }
}

resource "aws_subnet" "private-1c" {
  vpc_id = "${aws_vpc.default.id}"

  cidr_block = "10.0.6.0/24"
  availability_zone = "eu-west-1c"

  tags {
    Stack = "${var.stack}"
    Name = "Private Subnet 1c"
  }
}

resource "aws_eip" "nat-1a" {
  vpc = true
}

resource "aws_eip" "nat-1b" {
  vpc = true
}

resource "aws_eip" "nat-1c" {
  vpc = true
}

resource "aws_nat_gateway" "nat-gw-1a" {
  depends_on = ["aws_internet_gateway.default"]
  allocation_id = "${aws_eip.nat-1a.id}"
  subnet_id = "${aws_subnet.public-1a.id}"
}

resource "aws_nat_gateway" "nat-gw-1b" {
  depends_on = ["aws_internet_gateway.default"]
  allocation_id = "${aws_eip.nat-1b.id}"
  subnet_id = "${aws_subnet.public-1b.id}"
}

resource "aws_nat_gateway" "nat-gw-1c" {
  depends_on = ["aws_internet_gateway.default"]
  allocation_id = "${aws_eip.nat-1c.id}"
  subnet_id = "${aws_subnet.public-1c.id}"
}

resource "aws_route_table" "private-route-1a" {
  vpc_id = "${aws_vpc.default.id}"

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = "${aws_nat_gateway.nat-gw-1a.id}"
  }

  tags {
    Stack = "${var.stack}"
    Name = "Private routing"
  }
}

resource "aws_route_table" "private-route-1b" {
  vpc_id = "${aws_vpc.default.id}"

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = "${aws_nat_gateway.nat-gw-1b.id}"
  }

  tags {
    Stack = "${var.stack}"
    Name = "Private routing"
  }
}

resource "aws_route_table" "private-route-1c" {
  vpc_id = "${aws_vpc.default.id}"

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = "${aws_nat_gateway.nat-gw-1c.id}"
  }

  tags {
    Stack = "${var.stack}"
    Name = "Private routing"
  }
}

resource "aws_route_table_association" "private-1a" {
    subnet_id = "${aws_subnet.private-1a.id}"
    route_table_id = "${aws_route_table.private-route-1a.id}"
}

resource "aws_route_table_association" "private-1b" {
    subnet_id = "${aws_subnet.private-1b.id}"
    route_table_id = "${aws_route_table.private-route-1b.id}"
}

resource "aws_route_table_association" "private-1c" {
    subnet_id = "${aws_subnet.private-1c.id}"
    route_table_id = "${aws_route_table.private-route-1c.id}"
}

#dhcp search
resource "aws_vpc_dhcp_options" "search" {
    domain_name = "${var.stack}.${var.aws_root_zone}"
    domain_name_servers = ["AmazonProvidedDNS"]

    tags {
        Name = "${var.stack}-dhcp-search"
    }
}

resource "aws_vpc_dhcp_options_association" "search" {
    vpc_id = "${aws_vpc.default.id}"
    dhcp_options_id = "${aws_vpc_dhcp_options.search.id}"
}

resource "aws_vpn_gateway" "vpn_gw" {
    vpc_id = "${aws_vpc.default.id}"
}

# Security group for each host
resource "aws_security_group" "base-sg" {
  name = "${var.stack}-base-sg"
  description = "Allow outgoing traffic"

  vpc_id = "${aws_vpc.default.id}"

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  tags {
    Stack = "${var.stack}"
    Name = "${var.stack}-default"
  }

  lifecycle {
    create_before_destroy = true
  }
}

data "null_data_source" "vpc_conf" {
  inputs = {
    id = "${aws_vpc.default.id}"
    subnets = {
      public = [
        "${aws_subnet.public-1a.id}",
        "${aws_subnet.public-1b.id}",
        "${aws_subnet.public-1c.id}"
      ]
      private = [
        "${aws_subnet.private-1a.id}",
        "${aws_subnet.private-1b.id}",
        "${aws_subnet.private-1c.id}"
      ]
    }
    security_group = "${aws_security_group.base-sg.id}"
  }
}

output "vpc_conf" {
  value = "${data.null_data_source.vpc_conf.input}"
}
