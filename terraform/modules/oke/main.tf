terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.10.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

############################################
# DATA SOURCES
############################################

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_containerengine_node_pool_option" "node_pool_options" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_id
}


############################################
# OKE CLUSTER
############################################
resource "oci_containerengine_cluster" "main" {

  compartment_id = var.compartment_id
  name           = "togglemaster-oke"

  vcn_id = var.vcn_id
  kubernetes_version = "v1.34.2"

  lifecycle {
    ignore_changes = [
      kubernetes_version
    ]
  }

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = var.lb_subnet_id
  }

  options {
    service_lb_subnet_ids = [var.lb_subnet_id]
  }

}


############################################
# NODE POOL
############################################

resource "oci_containerengine_node_pool" "pool" {

  name           = "togglemaster-nodepool"
  cluster_id     = oci_containerengine_cluster.main.id
  compartment_id = var.compartment_id

  kubernetes_version = oci_containerengine_cluster.main.kubernetes_version

  node_shape = "VM.Standard.A1.Flex"

  node_config_details {

    size = 1

    placement_configs {

      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name

      subnet_id = var.node_subnet_id
    }
  }

  node_shape_config {
    ocpus         = 2
    memory_in_gbs = 16
  }

  node_source_details {
    source_type = "IMAGE"
    image_id    = data.oci_containerengine_node_pool_option.node_pool_options.sources[0].image_id
  }

  depends_on = [
    oci_containerengine_cluster.main
  ]
}