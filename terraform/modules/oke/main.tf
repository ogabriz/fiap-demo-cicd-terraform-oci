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

data "oci_containerengine_cluster_option" "cluster_options" {
  cluster_option_id = "all"
  compartment_id    = var.compartment_id
}

data "oci_containerengine_node_pool_option" "node_pool_options" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_id
}

locals {
  # Use the latest available Kubernetes version from OCI
  available_k8s_versions = data.oci_containerengine_cluster_option.cluster_options.kubernetes_versions
  kubernetes_version     = local.available_k8s_versions[length(local.available_k8s_versions) - 1]

  # Version without 'v' prefix for matching in image source names
  k8s_version_short = replace(local.kubernetes_version, "v", "")

  # Filter node pool images: prefer aarch64 (ARM for A1.Flex) matching our K8s version
  arm_images = [
    for s in data.oci_containerengine_node_pool_option.node_pool_options.sources :
    s if length(regexall("OKE-${local.k8s_version_short}", s.source_name)) > 0
    && length(regexall("aarch64", s.source_name)) > 0
  ]

  # Fallback: any image matching the K8s version (regardless of architecture)
  all_version_images = [
    for s in data.oci_containerengine_node_pool_option.node_pool_options.sources :
    s if length(regexall("OKE-${local.k8s_version_short}", s.source_name)) > 0
  ]

  node_pool_image_id = length(local.arm_images) > 0 ? local.arm_images[0].image_id : local.all_version_images[0].image_id
}


############################################
# OKE CLUSTER
############################################
resource "oci_containerengine_cluster" "main" {

  compartment_id = var.compartment_id
  name           = "Hackathon-oke"

  vcn_id             = var.vcn_id
  kubernetes_version = local.kubernetes_version

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

  name           = "Hackathon-nodepool"
  cluster_id     = oci_containerengine_cluster.main.id
  compartment_id = var.compartment_id

  kubernetes_version = local.kubernetes_version

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
    image_id    = local.node_pool_image_id
  }

  depends_on = [
    oci_containerengine_cluster.main
  ]
}