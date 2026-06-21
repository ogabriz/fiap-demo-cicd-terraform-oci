output "ngo_service_repo_id" {
  description = "OCID of the ngo-service container repository"
  type        = string
  value       = oci_artifacts_container_repository.ngo_service.id
}

output "donation_service_repo_id" {
  description = "OCID of the donation-service container repository"
  type        = string
  value       = oci_artifacts_container_repository.donation_service.id
}

output "volunteer_service_repo_id" {
  description = "OCID of the volunteer-service container repository"
  type        = string
  value       = oci_artifacts_container_repository.volunteer_service.id
}

output "ngo_service_repo_display_name" {
  description = "Display name of the ngo-service container repository"
  type        = string
  value       = oci_artifacts_container_repository.ngo_service.display_name
}

output "donation_service_repo_display_name" {
  description = "Display name of the donation-service container repository"
  type        = string
  value       = oci_artifacts_container_repository.donation_service.display_name
}

output "volunteer_service_repo_display_name" {
  description = "Display name of the volunteer-service container repository"
  type        = string
  value       = oci_artifacts_container_repository.volunteer_service.display_name
}
