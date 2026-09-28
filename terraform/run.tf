# Terraform creates the service with a placeholder image; every later revision comes from the
# deploy workflow (by digest), so Terraform must not fight it.
resource "google_cloud_run_v2_service" "app" {
  project             = var.project_id
  name                = "keyless-demo"
  location            = var.region
  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = local.sa_email["kcs-runtime"]
    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }
    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
    }
  }

  lifecycle {
    ignore_changes = [template, client, client_version]
  }
  depends_on = [google_project_service.apis]
}
