variable "compartment_id" {
  description = "OCID of the OCI compartment where the NoSQL table will be created"
  type        = string
}

variable "table_name" {
  description = "Name of the OCI NoSQL table to create for storing analytics events"
  type        = string
}