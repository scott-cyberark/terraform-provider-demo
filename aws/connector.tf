data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# Account id for the AWS-attribute policy target.
data "aws_caller_identity" "current" {}

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

# The connector-management chain, the connector install, and the access policy
# live in the shared module -- see idira.tf.
