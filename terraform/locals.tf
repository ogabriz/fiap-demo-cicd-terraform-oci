data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

locals {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
}