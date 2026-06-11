output "cluster_id" {
  value = oci_containerengine_cluster.main.id
}

output "kubernetes_version" {
  value = local.kubernetes_version
}

output "node_pool_image_id" {
  value = local.node_pool_image_id
}
