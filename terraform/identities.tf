locals {
  sas = {
    "kcs-publisher" = "Build job of release.yml on main: pushes, signs and attests the image"
    "kcs-deployer"  = "deploy.yml on main: verifies the signature, then deploys by digest"
    "kcs-runtime"   = "Runs the service. Holds no roles."
  }
}

resource "google_service_account" "sa" {
  for_each     = local.sas
  project      = var.project_id
  account_id   = each.key
  display_name = each.value
  depends_on   = [google_project_service.apis]
}

locals {
  sa_email = { for k, v in google_service_account.sa : k => v.email }
}

# ── who may become which identity ──
resource "google_service_account_iam_member" "publisher_wif" {
  service_account_id = google_service_account.sa["kcs-publisher"].name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.release_principal
}

resource "google_service_account_iam_member" "deployer_wif" {
  service_account_id = google_service_account.sa["kcs-deployer"].name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.deploy_principal
}

# the deploy workflow mints an ID token as the deployer to smoke-test the private service
resource "google_service_account_iam_member" "deployer_idtoken" {
  service_account_id = google_service_account.sa["kcs-deployer"].name
  role               = "roles/iam.serviceAccountOpenIdTokenCreator"
  member             = local.deploy_principal
}

# ── what each identity may do: all resource-scoped, nothing at project level ──
resource "google_artifact_registry_repository_iam_member" "publisher_push" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${local.sa_email["kcs-publisher"]}"
}

resource "google_artifact_registry_repository_iam_member" "deployer_read" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${local.sa_email["kcs-deployer"]}"
}

resource "google_cloud_run_v2_service_iam_member" "deployer_run" {
  for_each = toset(["roles/run.developer", "roles/run.invoker"])
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.app.name
  role     = each.value
  member   = "serviceAccount:${local.sa_email["kcs-deployer"]}"
}

resource "google_service_account_iam_member" "deployer_acts_as_runtime" {
  service_account_id = google_service_account.sa["kcs-runtime"].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${local.sa_email["kcs-deployer"]}"
}

# operator: read the service (dashboard-style checks) and push the "rogue" images used in the drill
resource "google_artifact_registry_repository_iam_member" "operator_write" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.writer"
  member     = "user:${var.admin_email}"
}

resource "google_cloud_run_v2_service_iam_member" "operator_invoke" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.app.name
  role     = "roles/run.invoker"
  member   = "user:${var.admin_email}"
}
