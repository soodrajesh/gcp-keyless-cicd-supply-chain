output "wif_provider" { value = google_iam_workload_identity_pool_provider.github.name }
output "publisher_sa" { value = local.sa_email["kcs-publisher"] }
output "deployer_sa" { value = local.sa_email["kcs-deployer"] }
output "runtime_sa" { value = local.sa_email["kcs-runtime"] }
output "artifact_repo" { value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}" }
output "service" { value = google_cloud_run_v2_service.app.name }
output "service_url" { value = google_cloud_run_v2_service.app.uri }
