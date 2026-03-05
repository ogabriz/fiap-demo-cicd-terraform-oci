
resource "oci_containerengine_cluster" "oke" {
  name               = "togglemaster-oke"
  compartment_id     = var.compartment_id
  vcn_id             = var.vcn_id
  kubernetes_version = "v1.29.1"
}
