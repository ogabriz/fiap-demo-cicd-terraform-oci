variable "compartment_id" {
  description = "OCID of the OCI compartment where the NoSQL table will be created"
  type        = string
}

variable "table_name" {
  description = "Name of the OCI NoSQL table to create for storing volunteer data"
  type        = string
}

variable "tags" {
  description = "Tags FinOps (freeform_tags) aplicadas a tabela NoSQL"
  type        = map(string)
  default     = {}
}
