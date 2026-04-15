variable "namespace" {
  description = "Namespace for observability"
  type        = string
  default     = "monitoring"
}

variable "cluster_id" {
  description = "OKE cluster ID"
  type        = string
}
