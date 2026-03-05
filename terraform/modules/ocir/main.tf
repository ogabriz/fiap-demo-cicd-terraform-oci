resource "oci_artifacts_container_repository" "repo" {
  compartment_id = var.compartment_id
  display_name   = "togglemaster/app"
  is_public      = false
}