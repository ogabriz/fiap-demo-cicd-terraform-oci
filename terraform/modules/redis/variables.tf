variable "compartment_id" {
  description = "OCID of the OCI compartment where the Redis compute instance will be created"
  type        = string
}

variable "subnet_id" {
  description = "OCID of the subnet where the Redis compute instance will be attached"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key content to be injected into the Redis instance for remote access"
  type        = string
}

variable "image_id" {
  description = "OCID of the OCI compute image used to provision the Redis instance"
  type        = string
}