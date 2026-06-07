output "oke_cluster_id" {
  value = module.oke.cluster_id
}

output "queue_id" {
  value       = module.queue.queue_id
  description = "OCID da OCI Queue (usar em OCI_QUEUE_ID)"
}

output "queue_messages_endpoint" {
  value       = module.queue.queue_messages_endpoint
  description = "Endpoint da OCI Queue (usar em OCI_QUEUE_ENDPOINT)"
}

output "nosql_table_id" {
  value       = module.nosql.table_id
  description = "OCID da tabela OCI NoSQL"
}
