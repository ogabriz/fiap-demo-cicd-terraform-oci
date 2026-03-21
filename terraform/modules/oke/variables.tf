variable "compartment_id" {
  description = "OCID of the OCI compartment where OKE cluster resources will be created"
  type        = string
}

variable "vcn_id" {
  description = "OCID of the VCN where the OKE cluster will be deployed"
  type        = string
}

variable "subnet_id" {
  description = "OCID of the subnet for OKE worker nodes (used by node pool placement config)"
  type        = string
}

variable "availability_domain" {
  description = "Availability Domain name where OKE node pool instances will be placed"
  type        = string
}

variable "node_image" {
  description = "OCID of the compute image used to provision OKE worker node instances"
  type        = string
}

variable "tenancy_ocid" {
  description = "OCI Tenancy OCID used to query availability domains"
  type        = string
}

variable "node_subnet_id" {
  description = "OCID of the subnet where OKE worker node instances will be placed"
  type        = string
}

variable "lb_subnet_id" {
  description = "OCID of the subnet used for OKE-managed Load Balancers"
  type        = string
}