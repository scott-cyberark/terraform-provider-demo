# The shared Idira wiring: connector-management network/pool/identifier, the SIA
# connector install, and the VM access policy. Everything cloud-specific is
# passed in; the module itself is identical for AWS and Azure.
module "idira" {
  source = "../modules/idira"

  demo_name          = var.demo_name
  policy_role_name   = var.policy_role_name
  policy_principals  = var.policy_principals
  ephemeral_username = var.ephemeral_username

  max_session_duration = var.max_session_duration
  idle_time            = var.idle_time
  time_zone            = var.time_zone
  access_window_days   = var.access_window_days

  # Connector installs onto the public-subnet EC2 host over SSH. ON-PREMISE is
  # what the demo has run on; the install is SSH-based regardless of type.
  connector_type             = "ON-PREMISE"
  connector_target_machine   = aws_instance.connector.public_ip
  connector_username         = "ec2-user"
  connector_private_key_path = local_sensitive_file.connector_key.filename

  # AWS_SUBNET values must be "<vpc-id>/<subnet-id>" -- a bare subnet id is
  # rejected with a 400 the provider docs do not mention.
  pool_identifier_type  = "AWS_SUBNET"
  pool_identifier_value = "${aws_vpc.demo.id}/${aws_subnet.private.id}"

  policy_target_mode = var.policy_target_mode
  target = {
    account_ids  = [data.aws_caller_identity.current.account_id]
    regions      = [var.aws_region]
    network_ids  = [aws_vpc.demo.id]
    tag_key      = "Role"
    tag_value    = aws_instance.target.tags["Role"]
    private_ip   = aws_instance.target.private_ip
    logical_name = var.demo_name
  }

  # The connector install SSHes into the public-subnet host, so its networking
  # must exist first. Gating the whole module on these is harmless.
  depends_on = [
    aws_vpc_security_group_ingress_rule.connector_ssh_from_admin,
    aws_vpc_security_group_egress_rule.connector_all,
    aws_route_table_association.public,
  ]
}
