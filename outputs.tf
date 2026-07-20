output "target_private_ip" {
  description = "Private address of the demo target. Not routable from outside the VPC."
  value       = aws_instance.target.private_ip
}

output "target_private_dns" {
  description = "Internal DNS name of the demo target."
  value       = aws_instance.target.private_dns
}

output "target_instance_id" {
  description = "Instance ID of the demo target, for the describe-instances proof."
  value       = aws_instance.target.id
}

output "target_public_ip" {
  description = "Always empty. This is the claim the whole demo rests on."
  value       = aws_instance.target.public_ip
}

output "connector_public_ip" {
  description = "Public address of the SIA connector host."
  value       = aws_instance.connector.public_ip
}

output "connector_pool_id" {
  description = "Connector Management pool the connector registered into."
  value       = idsec_cmgr_pool.demo.pool_id
}

output "policy_id" {
  description = "The VM access policy created for this demo."
  value       = idsec_policy_vm.demo.metadata.policy_id
}

output "ephemeral_username" {
  description = "The user SIA provisions at connect time. Does not exist on the target beforehand."
  value       = var.ephemeral_username
}

output "connect" {
  description = "How to reach the target through SIA."
  value       = <<-EOT

    Connect via the SIA CLI:
      sia ssh connect --target ${aws_instance.target.private_ip}

    Or from the Idira portal: Secure Infrastructure Access -> Connect -> SSH,
    then pick ${aws_instance.target.private_dns}.

    You will land as '${var.ephemeral_username}' on a certificate valid for this
    session only.
  EOT
}

output "proof" {
  description = "Commands that substantiate the demo's claims. Run these on screen."
  value       = <<-EOT

    The target has no public IP:
      aws ec2 describe-instances --region ${var.aws_region} \
        --instance-ids ${aws_instance.target.id} \
        --query 'Reservations[].Instances[].PublicIpAddress' --output text

    Its only inbound rule is the connector's security group:
      aws ec2 describe-security-group-rules --region ${var.aws_region} \
        --filters Name=group-id,Values=${aws_security_group.target.id} \
        --query 'SecurityGroupRules[?!IsEgress].[IpProtocol,FromPort,ReferencedGroupInfo.GroupId,CidrIpv4]' \
        --output table

    Its subnet has no route off the VPC:
      aws ec2 describe-route-tables --region ${var.aws_region} \
        --route-table-ids ${aws_route_table.private.id} \
        --query 'RouteTables[].Routes[]' --output table
  EOT
}
