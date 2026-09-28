variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "github_repo" {
  description = "owner/name of the only repository allowed to authenticate."
  type        = string
}

variable "github_repo_id" {
  description = "Numeric repository id (immutable, unlike the name): a deleted-and-recreated or renamed repo cannot inherit trust."
  type        = string
}

variable "github_owner_id" {
  description = "Numeric id of the owning user/org."
  type        = string
}

variable "suffix" {
  description = "Per-deployment suffix. Workload Identity pools are soft-deleted for 30 days and their ids cannot be reused, so each build gets a fresh one."
  type        = string
}

variable "admin_email" {
  type = string
}
