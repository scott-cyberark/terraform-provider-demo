output "target_private_ip" {
  description = "Private address of the demo target. Not routable from outside the VNet."
  value       = azurerm_network_interface.target.private_ip_address
}

output "target_vm_name" {
  description = "Name of the demo target VM."
  value       = azurerm_linux_virtual_machine.target.name
}

output "target_vm_id" {
  description = "Azure VM id of the demo target -- usable as a cybr-ssh target."
  value       = azurerm_linux_virtual_machine.target.virtual_machine_id
}

output "connector_public_ip" {
  description = "Public address of the SIA connector VM."
  value       = azurerm_public_ip.connector.ip_address
}

output "connector_pool_id" {
  description = "Connector Management pool the connector registered into."
  value       = module.idira.pool_id
}

output "policy_id" {
  description = "The VM access policy created for this demo."
  value       = module.idira.policy_id
}

output "resource_group" {
  description = "Resource group holding everything; deleting it removes the demo."
  value       = azurerm_resource_group.demo.name
}

output "connect" {
  description = "How to reach the target through SIA."
  value       = <<-EOT

    Target VM:  ${azurerm_linux_virtual_machine.target.name}
    VM id:      ${azurerm_linux_virtual_machine.target.virtual_machine_id}
    Private IP: ${azurerm_network_interface.target.private_ip_address}

    Connect with cybr-ssh -- either identifier works:
      cybr-ssh ${azurerm_network_interface.target.private_ip_address}
      cybr-ssh ${azurerm_linux_virtual_machine.target.virtual_machine_id}

    Or plain ssh through the SIA proxy (replace <you> with your Idira user):
      ssh <you>#${var.idsec_subdomain}@${azurerm_network_interface.target.private_ip_address}@${var.idsec_subdomain}.ssh.cyberark.cloud

    You land as '${var.ephemeral_username}' on a certificate valid for this
    session only.
  EOT
}

output "proof" {
  description = "Commands that substantiate the demo's claims. Run these on screen."
  value       = <<-EOT

    The target has no public IP:
      az vm list-ip-addresses -g ${azurerm_resource_group.demo.name} \
        -n ${azurerm_linux_virtual_machine.target.name} \
        --query '[].virtualMachine.network.publicIpAddresses' -o tsv

    Its NSG allows inbound only on 22 from the connector subnet, and denies egress:
      az network nsg rule list -g ${azurerm_resource_group.demo.name} \
        --nsg-name ${var.demo_name}-target-nsg \
        --query '[].{name:name,dir:direction,access:access,port:destinationPortRange,src:sourceAddressPrefix,dst:destinationAddressPrefix}' \
        -o table
  EOT
}
