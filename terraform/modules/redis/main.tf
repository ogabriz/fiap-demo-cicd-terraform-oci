resource "oci_redis_cluster" "redis" {
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain

  display_name = "togglemaster-redis"
  node_count   = 1
  node_shape   = "REDIS_STANDARD_SMALL"

  subnet_id = var.subnet_id
}