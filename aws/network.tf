locals {
  common_tags = {
    Demo      = "idira-sia"
    ManagedBy = "terraform"
    Name      = var.demo_name
  }

  # The connector is installed over SSH from wherever Terraform runs, so that
  # address needs to reach port 22 on the connector. Auto-detect unless pinned.
  admin_cidr = coalesce(
    var.admin_cidr,
    "${chomp(data.http.my_ip.response_body)}/32",
  )
}

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "demo" {
  cidr_block = var.vpc_cidr

  # Gives the target an internal DNS name, which is what makes it addressable
  # by name in SIA without ever having a public record.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.demo_name}-vpc" }
}

resource "aws_internet_gateway" "demo" {
  vpc_id = aws_vpc.demo.id
  tags   = { Name = "${var.demo_name}-igw" }
}

# --- Public subnet: the SIA connector only ----------------------------------
# The connector needs outbound internet to maintain its tunnel to the tenant.

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "${var.demo_name}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.demo.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo.id
  }

  tags = { Name = "${var.demo_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- Private subnet: the target server only ---------------------------------
# Deliberately has no route to the internet gateway and no NAT gateway. The
# target cannot reach the internet and the internet cannot reach it. Worth
# showing on screen -- it is the whole point of the demo.

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = { Name = "${var.demo_name}-private" }
}

# An explicit route table with no routes beyond the VPC-local one. Without this
# the subnet would inherit the main route table, and "it has no routes" is a
# much weaker claim than pointing at an empty table.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.demo.id
  tags   = { Name = "${var.demo_name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# --- Security groups --------------------------------------------------------

resource "aws_security_group" "connector" {
  name        = "${var.demo_name}-connector"
  description = "SIA connector: SSH in from the operator during install, egress to the Idira tenant"
  vpc_id      = aws_vpc.demo.id

  tags = { Name = "${var.demo_name}-connector-sg" }
}

# Needed only while idsec_sia_access_connector installs the connector software.
# Safe to revoke afterwards; the connector dials out and never needs inbound.
resource "aws_vpc_security_group_ingress_rule" "connector_ssh_from_admin" {
  security_group_id = aws_security_group.connector.id
  description       = "SSH from the operator, for connector installation"
  cidr_ipv4         = local.admin_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "connector_all" {
  security_group_id = aws_security_group.connector.id
  description       = "Outbound to the Idira tenant"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "target" {
  name        = "${var.demo_name}-target"
  description = "Demo target: SSH from the SIA connector and nothing else"
  vpc_id      = aws_vpc.demo.id

  tags = { Name = "${var.demo_name}-target-sg" }
}

# The only way in. Not a CIDR, not a bastion, not your laptop -- the connector's
# security group. Put this on screen next to a live SSH session.
resource "aws_vpc_security_group_ingress_rule" "target_ssh_from_connector" {
  security_group_id            = aws_security_group.target.id
  description                  = "SSH from the SIA connector only"
  referenced_security_group_id = aws_security_group.connector.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

# No egress rules at all. The target initiates nothing.
