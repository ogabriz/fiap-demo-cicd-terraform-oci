terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }
}

resource "oci_queue_queue" "main" {

  compartment_id = var.compartment_id
  display_name   = "togglemaster-queue"

  visibility_in_seconds = 30
  timeout_in_seconds    = 30

  retention_in_seconds  = 604800

}