output "pool_id" {
  description = "Connector Management pool the connector registered into."
  value       = idsec_cmgr_pool.demo.pool_id
}

output "network_id" {
  description = "Connector Management network id."
  value       = idsec_cmgr_network.demo.network_id
}

output "connector_id" {
  description = "Installed SIA connector id."
  value       = idsec_sia_access_connector.demo.connector_id
}

output "policy_id" {
  description = "The VM access policy created for this demo."
  value       = idsec_policy_vm.demo.metadata.policy_id
}
