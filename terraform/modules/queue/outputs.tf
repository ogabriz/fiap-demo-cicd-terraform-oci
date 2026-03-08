output "queue_id" {
  value = oci_queue_queue.main.id
}

output "queue_messages_endpoint" {
  value = oci_queue_queue.main.messages_endpoint
}