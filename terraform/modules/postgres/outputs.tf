output "postgres_public_ip" {
  value = oci_core_instance.postgres.public_ip
}

output "postgres_private_ip" {
  value = oci_core_instance.postgres.private_ip
}
