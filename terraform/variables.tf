variable "tenancy_ocid" {
  description = "OCID of the OCI tenancy where resources will be provisioned"
  type        = string
}

variable "user_ocid" {
  description = "OCID of the OCI user used for API authentication"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the OCI API key used for authentication"
  type        = string
}

variable "region" {
  description = "OCI region where resources will be deployed (e.g. sa-saopaulo-1)"
  type        = string
}

variable "compartment_id" {
  description = "OCID of the OCI compartment where all resources will be created"
  type        = string
}

variable "availability_domain" {
  description = "Availability Domain name where compute resources will be placed (e.g. AD-1)"
  type        = string
}

variable "oke_image" {
  description = "OCID of the OCI compute image used for OKE worker nodes"
  type        = string
}

variable "discord_webhook_url" {
  description = "Discord Webhook URL for alert notifications"
  type        = string
  default     = "https://discord.com/api/webhooks/1498992712941305999/6tqHDK7YC_sxTDS-WlOvM2W4JOKZF9WeQ36N3qQql_UpARCPX2pC0wy-I4wpdTe--VOc"
  sensitive   = true
}

variable "newrelic_license_key" {
  description = "New Relic License Key for OTLP telemetry export"
  type        = string
  default     = ""
  sensitive   = true
}

# ---------------------------------------------------------------------------
# FinOps — Tagging Strategy
# ---------------------------------------------------------------------------
variable "common_tags" {
  description = "Tags FinOps obrigatorias aplicadas a todos os recursos OCI provisionados via Terraform (freeform_tags)"
  type        = map(string)
  default = {
    Project     = "SolidaryTech"
    Environment = "Production"
    CostCenter  = "NGO-Core"
    ManagedBy   = "Terraform"
  }
}
