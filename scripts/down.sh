#!/usr/bin/env bash
# Delete everything this repo created in Google Cloud and the GitHub variables that pointed at it.
#   ./scripts/down.sh            destroy
#   ./scripts/down.sh --purge    also delete this repo's Terraform state (and the bucket if now empty)
source "$(dirname "$0")/lib.sh"
need gcloud; need terraform
PURGE=0; [ "${1:-}" = "--purge" ] && PURGE=1

log "Project $PROJECT_ID — destroying everything managed by this repo"
tf_env; tf_init
$TF destroy -input=false -auto-approve
ok "cloud resources destroyed"
if command -v gh >/dev/null 2>&1; then
  for v in WIF_PROVIDER PUBLISHER_SA DEPLOYER_SA PROJECT_ID REGION SERVICE_NAME; do
    gh variable delete "$v" --repo "$GH_REPO" >/dev/null 2>&1 || true
  done
  ok "GitHub repository variables removed (workflows can no longer authenticate)"
fi
rm -rf "$ROOT/.test-tmp" "$ROOT/.deploy-suffix"

if [ "$PURGE" = 1 ]; then
  gcloud storage rm -r "gs://$STATE_BUCKET/keyless-cicd/" --quiet >/dev/null 2>&1 || true
  if [ -z "$(gcloud storage ls "gs://$STATE_BUCKET/" 2>/dev/null)" ]; then
    gcloud storage rm -r "gs://$STATE_BUCKET" --quiet >/dev/null 2>&1 || true; ok "state prefix and (now empty) bucket removed"
  else ok "state prefix removed; bucket kept because other stacks still use it"; fi
else log "Kept state bucket gs://$STATE_BUCKET (a few KB; --purge removes it)"; fi

log "Anything left?"
echo "  Cloud Run service (keyless-demo):   $(gcloud run services list --project "$PROJECT_ID" --region "$REGION" --format='value(metadata.name)' 2>/dev/null | grep -c '^keyless-demo$' || true)"
echo "  Artifact Registry (keyless):        $(gcloud artifacts repositories list --project "$PROJECT_ID" --location "$REGION" --format='value(name)' 2>/dev/null | grep -c '/keyless$' || true)"
echo "  Service accounts (kcs-*):           $(gcloud iam service-accounts list --project "$PROJECT_ID" --format='value(email)' 2>/dev/null | grep -c '^kcs-' || true)"
echo "  Active WIF pools (gh-*):            $(gcloud iam workload-identity-pools list --location global --project "$PROJECT_ID" --format='value(name)' 2>/dev/null | grep -c '/gh-' || true)"
log "DONE (deleted WIF pools stay soft-deleted for 30 days; the next build uses a fresh suffix)"
