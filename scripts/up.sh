#!/usr/bin/env bash
# Build everything end to end, then prove it works:
#   state bucket -> Workload Identity pool/provider + 3 service accounts + registry + private Cloud Run
#   service -> GitHub repository variables -> the REAL release pipeline runs on GitHub -> live tests.
# The repo must already be pushed to GitHub (the pipeline it triggers is the one on origin/main).
#   ./scripts/up.sh [--skip-tests]
source "$(dirname "$0")/lib.sh"
SKIP_TESTS=0; [ "${1:-}" = "--skip-tests" ] && SKIP_TESTS=1
need gcloud; need terraform; need gh; need docker; need cosign; need jq

[ "$(git rev-parse HEAD)" = "$(git ls-remote origin refs/heads/main | cut -f1)" ] \
  || die "local HEAD is not what origin/main has — push first (the pipeline runs the pushed workflows)"
log "Project $PROJECT_ID · $REGION · trusting only $GH_REPO · suffix $SUFFIX"

log "1/6 Terraform state bucket"
"$ROOT/scripts/bootstrap.sh" "$PROJECT_ID" "$REGION" >/dev/null && ok "gs://$STATE_BUCKET"
tf_env; tf_init

log "2/6 Workload Identity, service accounts, registry, private Cloud Run service"
$TF apply -input=false -auto-approve
out() { $TF output -raw "$1"; }

log "3/6 GitHub repository variables (identifiers only — there are no secrets to store)"
for kv in "WIF_PROVIDER=$(out wif_provider)" "PUBLISHER_SA=$(out publisher_sa)" "DEPLOYER_SA=$(out deployer_sa)" \
          "PROJECT_ID=$PROJECT_ID" "REGION=$REGION" "SERVICE_NAME=$(out service)"; do
  gh variable set "${kv%%=*}" --repo "$GH_REPO" --body "${kv#*=}" >/dev/null && ok "${kv%%=*}"
done
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet >/dev/null 2>&1 && ok "local docker credential helper for verification"

log "4/6 Run the real release pipeline on GitHub Actions"
read -r RUN CONCLUSION < <(run_workflow release.yml main)
ok "release run $RUN: $CONCLUSION  (https://github.com/$GH_REPO/actions/runs/$RUN)"
[ "$CONCLUSION" = success ] || { gh run view "$RUN" --repo "$GH_REPO" --log-failed 2>&1 | tail -30; die "release pipeline failed"; }

log "5/6 What is running"
DIGEST="$(served_digest)"; ok "Cloud Run serves $IMAGE@$DIGEST"
"$ROOT/scripts/verify.sh" "$DIGEST"

if [ "$SKIP_TESTS" = 1 ]; then log "Skipping tests"; else log "6/6 Live test suite"; "$ROOT/scripts/test.sh"; fi
log "DONE — tear down with ./scripts/down.sh"
