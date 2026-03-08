output "postgres_public_ip" {
  value = oci_core_instance.postgres.public_ip
}