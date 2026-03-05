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
  type = string
}

variable "db_admin_password" {
  type      = string
  sensitive = true
}