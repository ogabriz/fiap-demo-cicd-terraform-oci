resource "oci_queue_queue" "main" {

  compartment_id = var.compartment_id
  display_name   = "togglemaster-queue"

  visibility_in_seconds = 30
  timeout_in_seconds    = 30

  retention_in_seconds  = 1209600

}