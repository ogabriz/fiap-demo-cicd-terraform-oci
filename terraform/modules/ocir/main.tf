
data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_id
}

output "namespace" {
  value = data.oci_objectstorage_namespace.ns.namespace
}