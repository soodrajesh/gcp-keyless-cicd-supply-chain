#!/usr/bin/env bash
# Shared helpers. Sourced, not executed.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m✘ %s\033[0m\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1${2:+ ($2)}"; }

[ -f "$ROOT/deploy.env" ] && set -a && . "$ROOT/deploy.env" && set +a

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${REGION:-europe-west1}"
ADMIN_EMAIL="${ADMIN_EMAIL:-$(gcloud config get-value account 2>/dev/null)}"
[ -n "$PROJECT_ID" ] || die "no project: set PROJECT_ID in deploy.env or run 'gcloud config set project'"

# The repository whose workflows are trusted = this checkout's origin.
GH_REPO="${GH_REPO:-$(git remote get-url origin 2>/dev/null | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')}"
[ -n "$GH_REPO" ] || die "no git remote 'origin': push this repo to GitHub first"

TF="terraform -chdir=$ROOT/terraform"
STATE_BUCKET="${PROJECT_ID}-tfstate"
AR_REPO="${REGION}-docker.pkg.dev/${PROJECT_ID}/keyless"
# shellcheck disable=SC2034 # used by the scripts that source this file
IMAGE="${AR_REPO}/app"

# Per-deployment suffix: WIF pools are soft-deleted for 30 days and ids can't be reused.
[ -s "$ROOT/.deploy-suffix" ] || head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$ROOT/.deploy-suffix"
SUFFIX="$(cat "$ROOT/.deploy-suffix")"

tf_env() {
  local repo_id owner_id
  repo_id="$(gh api "repos/$GH_REPO" --jq .id)"; owner_id="$(gh api "repos/$GH_REPO" --jq .owner.id)"
  export TF_VAR_project_id="$PROJECT_ID" TF_VAR_region="$REGION" TF_VAR_admin_email="$ADMIN_EMAIL" \
         TF_VAR_github_repo="$GH_REPO" TF_VAR_suffix="$SUFFIX" \
         TF_VAR_github_repo_id="$repo_id" TF_VAR_github_owner_id="$owner_id"
}
tf_init() { $TF init -input=false -backend-config="bucket=$STATE_BUCKET" >/dev/null; }

# The digest Cloud Run is serving right now.
served_digest() {
  gcloud run services describe keyless-demo --project "$PROJECT_ID" --region "$REGION" \
    --format='value(spec.template.spec.containers[0].image)' | sed 's/.*@//'
}

# Run a workflow and wait for it. Prints "<run-id> <conclusion>".
#   run_workflow <file.yml> <ref> [-f key=value ...]
run_workflow() {
  local wf="$1" ref="$2"; shift 2
  local before id=""
  before="$(gh run list --repo "$GH_REPO" --workflow "$wf" --limit 1 --json databaseId --jq '.[0].databaseId // 0')"
  gh workflow run "$wf" --repo "$GH_REPO" --ref "$ref" "$@" >/dev/null
  local end=$(( $(date +%s) + 90 ))
  while [ -z "$id" ] || [ "$id" = "$before" ]; do
    [ "$(date +%s)" -lt "$end" ] || die "run of $wf never appeared"
    sleep 3
    id="$(gh run list --repo "$GH_REPO" --workflow "$wf" --limit 1 --json databaseId --jq '.[0].databaseId // 0')"
  done
  gh run watch "$id" --repo "$GH_REPO" >/dev/null 2>&1 || true
  echo "$id $(gh run view "$id" --repo "$GH_REPO" --json conclusion --jq .conclusion)"
}
