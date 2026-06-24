variable "compartment_id" {
  description = "OCID of the OCI compartment where container image repositories (OCIR) will be created"
  type        = string
}

variable "tags" {
  description = "Tags FinOps (freeform_tags) aplicadas aos repositorios do Container Registry"
  type        = map(string)
  default     = {}
}
