variable "tenancy_ocid" {
  type = string
}

variable "user_ocid" {
  type = string
}

variable "fingerprint" {
  type = string
}

variable "region" {
  type = string
}

variable "compartment_id" {
  type = string
}

variable "ssh_public_key" {
  description = "SSH public key"
}

variable "image_id" {
  description = "OCI image id used for compute instances"
  type        = string
}

variable "availability_domain" {
  description = "Availability Domain where resources will be created"
  type        = string
}

variable "oke_image" {
  description = "Image OCID for OKE worker nodes"
  type        = string
}