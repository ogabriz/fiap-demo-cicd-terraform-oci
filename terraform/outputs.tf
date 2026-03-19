output "redis_private_ip" {
  value = module.redis.redis_private_ip
}

output "redis_hostname" {
  value = module.redis.redis_hostname
}

output "postgres_private_ip" {
  value = module.postgres.postgres_private_ip
}

output "oke_cluster_id" {
  value = module.oke.cluster_id
}
