# GitHub Actions authenticates with a short-lived OIDC token it mints for each job. Google's
# Security Token Service exchanges it for a federated token only if the provider's attribute
# condition accepts the claims; a second gate (the IAM binding on each service account) then
# decides WHICH workflow file on WHICH ref may become WHICH identity. No key exists anywhere.
resource "google_iam_workload_identity_pool" "gh" {
  project                   = var.project_id
  workload_identity_pool_id = "gh-${var.suffix}"
  display_name              = "GitHub Actions"
  depends_on                = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.gh.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_id"    = "assertion.repository_id"
    "attribute.ref"              = "assertion.ref"
    "attribute.job_workflow_ref" = "assertion.job_workflow_ref"
    "attribute.event_name"       = "assertion.event_name"
  }

  # Gate 1: only tokens from THIS repository (by immutable numeric id) and its owner.
  attribute_condition = "assertion.repository_id == '${var.github_repo_id}' && assertion.repository_owner_id == '${var.github_owner_id}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

locals {
  pool = google_iam_workload_identity_pool.gh.name
  # Gate 2: the exact workflow file, on main. job_workflow_ref is the file that contains the
  # running job (for a reusable workflow, the CALLED file), so a workflow on a branch, or any
  # other file in the same repo, is a different principal and gets nothing.
  release_principal = "principalSet://iam.googleapis.com/${local.pool}/attribute.job_workflow_ref/${var.github_repo}/.github/workflows/release.yml@refs/heads/main"
  deploy_principal  = "principalSet://iam.googleapis.com/${local.pool}/attribute.job_workflow_ref/${var.github_repo}/.github/workflows/deploy.yml@refs/heads/main"
}
