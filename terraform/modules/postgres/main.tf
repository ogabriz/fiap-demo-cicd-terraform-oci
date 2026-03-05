resource "oci_psql_db_system" "postgres" {
  count               = 3
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain

  display_name = "togglemaster-postgres-${count.index}"
  shape        = "VM.Standard.E4.Flex"
  db_version   = "14"

  admin_username = "postgres"
  admin_password = var.db_admin_password

  network_details {
    subnet_id = var.subnet_id
  }

  storage_details {
    system_type = "OCI_OPTIMIZED_STORAGE"
    size_in_gbs = 50
  }
}