variable "compartment_id" {
  description = "OCID of the OCI compartment where the OCI Queue will be created"
  type        = string
}

variable "tags" {
  description = "Tags FinOps (freeform_tags) aplicadas a fila OCI Queue"
  type        = map(string)
  default     = {}
}
