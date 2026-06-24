terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }
}

resource "oci_artifacts_container_repository" "ngo_service" {
  compartment_id = var.compartment_id
  display_name   = "hackathon-repo/ngo-service"
  is_public      = false

  freeform_tags = var.tags
}

resource "oci_artifacts_container_repository" "donation_service" {
  compartment_id = var.compartment_id
  display_name   = "hackathon-repo/donation-service"
  is_public      = false

  freeform_tags = var.tags
}

resource "oci_artifacts_container_repository" "volunteer_service" {
  compartment_id = var.compartment_id
  display_name   = "hackathon-repo/volunteer-service"
  is_public      = false

  freeform_tags = var.tags
}
