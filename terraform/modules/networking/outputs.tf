output "vcn_id" {
  value = oci_core_vcn.main.id
}

output "workers_subnet_id" {
  value = oci_core_subnet.workers.id
}

output "db_subnet_id" {
  value = oci_core_subnet.db.id
}