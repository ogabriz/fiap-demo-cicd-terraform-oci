variable "namespace" {
  description = "Namespace for observability"
  type        = string
  default     = "monitoring"
}

variable "cluster_id" {
  description = "OKE cluster ID"
  type        = string
}

variable "redis_host" {
  description = "Redis host IP or hostname"
  type        = string
}

variable "discord_webhook_url" {
  description = "Discord Webhook URL for alert notifications"
  type        = string
  sensitive   = true
}
