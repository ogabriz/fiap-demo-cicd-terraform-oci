resource "oci_containerengine_cluster" "main" {

  compartment_id     = var.compartment_id
  kubernetes_version = "v1.29.1"

  name = "togglemaster-oke"

  vcn_id = var.vcn_id

  endpoint_config {
    is_public_ip_enabled = true

    subnet_id = var.subnet_id
  }

  options {

    service_lb_subnet_ids = [
      var.subnet_id
    ]

  }
}

resource "oci_containerengine_node_pool" "pool" {

  cluster_id     = oci_containerengine_cluster.main.id
  compartment_id = var.compartment_id
  name           = "togglemaster-nodepool"

  kubernetes_version = oci_containerengine_cluster.main.kubernetes_version

  node_shape = "VM.Standard.A1.Flex"

  node_config_details {

    size = 1

    placement_configs {

      availability_domain = var.availability_domain
      subnet_id           = var.subnet_id

    }
  }

  node_shape_config {

    ocpus         = 1
    memory_in_gbs = 6
  }

  node_source_details {

    image_id    = var.node_image
    source_type = "image"
  }

}