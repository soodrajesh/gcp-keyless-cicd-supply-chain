resource "google_artifact_registry_repository" "images" {
  project       = var.project_id
  location      = var.region
  repository_id = "keyless"
  format        = "DOCKER"
  description   = "Images built and signed by GitHub Actions. Tags are immutable."
  docker_config {
    immutable_tags = true
  }
  depends_on = [google_project_service.apis]
}
