data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# --- Connector SSH keypair --------------------------------------------------
# Generated per-apply and destroyed with everything else, so the demo leaves
# nothing behind in ~/.ssh and needs no pre-existing key.

resource "tls_private_key" "connector" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "connector" {
  key_name   = "${var.demo_name}-connector"
  public_key = tls_private_key.connector.public_key_openssh
}

# idsec_sia_access_connector takes a private key *path*, so it has to hit disk.
resource "local_sensitive_file" "connector_key" {
  content         = tls_private_key.connector.private_key_pem
  filename        = "${path.module}/keys/${var.demo_name}-connector.pem"
  file_permission = "0600"
}

# --- Connector host ---------------------------------------------------------

resource "aws_instance" "connector" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.connector_instance_type
  key_name                    = aws_key_pair.connector.key_name
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.connector.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "${var.demo_name}-connector" }
}

# --- Connector Management: network -> pool -> identifier --------------------

resource "idsec_cmgr_network" "demo" {
  name = var.demo_name
}

resource "idsec_cmgr_pool" "demo" {
  name                 = "${var.demo_name}-pool"
  description          = "Connector pool for the ${var.demo_name} environment, managed by Terraform."
  assigned_network_ids = [idsec_cmgr_network.demo.network_id]
}

# Tells SIA which pool can reach a given target. Identifying the pool by the
# exact AWS subnet Terraform just created is a stronger demo beat than a
# wildcard FQDN: the pool is scoped to this subnet and nothing else.
resource "idsec_cmgr_pool_identifier" "private_subnet" {
  pool_id = idsec_cmgr_pool.demo.pool_id
  type    = "AWS_SUBNET"
  value   = aws_subnet.private.id
}

# --- Connector installation -------------------------------------------------

resource "idsec_sia_access_connector" "demo" {
  connector_type    = "ON-PREMISE"
  connector_os      = "linux"
  connector_pool_id = idsec_cmgr_pool.demo.pool_id

  target_machine   = aws_instance.connector.public_ip
  username         = "ec2-user"
  private_key_path = local_sensitive_file.connector_key.filename

  # This resource starts SSHing the moment the EC2 API reports the instance
  # running, which is well before cloud-init has sshd accepting connections.
  # Without these retries it is the single most likely thing to fail mid-demo.
  retry_count = 20
  retry_delay = 15

  # If a destroy is interrupted, the connector can be left registered in the
  # tenant while its host is gone. This lets a re-run clean it up rather than
  # leaving an orphan that a later demo trips over.
  force_delete = true

  depends_on = [
    aws_vpc_security_group_ingress_rule.connector_ssh_from_admin,
    aws_vpc_security_group_egress_rule.connector_all,
    aws_route_table_association.public,
  ]
}
