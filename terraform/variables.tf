variable "tenancy_ocid" {
  description = "OCID of the OCI tenancy where resources will be provisioned"
  type        = string
}

variable "user_ocid" {
  description = "OCID of the OCI user used for API authentication"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the OCI API key used for authentication"
  type        = string
}

variable "region" {
  description = "OCI region where resources will be deployed (e.g. sa-vinhedo-1)"
  type        = string
}

variable "compartment_id" {
  description = "OCID of the OCI compartment where all resources will be created"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key content to be injected into compute instances for remote access"
  type        = string
}

variable "image_id" {
  description = "OCID of the OCI compute image used for provisioning VM instances"
  type        = string
}

variable "availability_domain" {
  description = "Availability Domain name where compute resources will be placed (e.g. AD-1)"
  type        = string
}

variable "oke_image" {
  description = "OCID of the OCI compute image used for OKE worker nodes"
  type        = string
}