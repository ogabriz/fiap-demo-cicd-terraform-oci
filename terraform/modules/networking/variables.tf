variable "compartment_id" {
  description = "OCID of the OCI compartment where networking resources (VCN, subnets, gateways) will be created"
  type        = string
}

variable "tags" {
  description = "Tags FinOps (freeform_tags) aplicadas aos recursos de rede"
  type        = map(string)
  default     = {}
}
