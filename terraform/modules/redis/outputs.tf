output "redis_private_ip" {
  value = oci_core_instance.redis.private_ip
}

output "redis_hostname" {
  value = "${oci_core_instance.redis.create_vnic_details[0].hostname_label}.${data.oci_core_subnet.redis_subnet.dns_label}.${data.oci_core_vcn.redis_vcn.dns_label}.oraclevcn.com"
}

data "oci_core_subnet" "redis_subnet" {
  subnet_id = var.subnet_id
}

data "oci_core_vcn" "redis_vcn" {
  vcn_id = data.oci_core_subnet.redis_subnet.vcn_id
}
