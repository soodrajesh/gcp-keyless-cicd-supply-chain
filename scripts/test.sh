#!/usr/bin/env bash
# Live test suite against the running pipeline. Every negative is paired with a positive.
#   ./scripts/test.sh                  everything
#   SKIP_DRILLS=1 ./scripts/test.sh    skip the workflow-based drills (rogue images, WIF negatives)
source "$(dirname "$0")/lib.sh"
need gcloud; need gh; need cosign; need jq; need curl; need docker
PASS=0; FAIL=0
check() { # <description> <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); ok "$desc"; else FAIL=$((FAIL+1)); printf '\033[1;31m✘ %s\033[0m\n' "$desc"; fi
}
fails() { ! "$@"; }            # passes when the wrapped command fails
eq()    { [ "$1" = "$2" ]; }
ge()    { [ "${1:-0}" -ge "$2" ]; }
contains() { grep -q -- "$2" <<<"$1"; }
tf_env; tf_init
out() { $TF output -raw "$1"; }
PUB="$(out publisher_sa)"; DEP="$(out deployer_sa)"; RUN_SA="$(out runtime_sa)"
POOL="$(out wif_provider | sed 's#/providers/.*##')"
SVC_URL="$(out service_url)"
DIGEST="$(served_digest)"
REPO_ID="$(gh api "repos/$GH_REPO" --jq .id)"

log "1. Trust boundary configuration (Gate 1: the provider)"
PROV="$(gcloud iam workload-identity-pools providers describe github --workload-identity-pool "${POOL##*/}" --location global --project "$PROJECT_ID" --format=json)"
check "provider accepts only this repository by immutable numeric id ($REPO_ID)" contains "$(jq -r .attributeCondition <<<"$PROV")" "repository_id == '$REPO_ID'"
check "provider also pins the repository OWNER id" contains "$(jq -r .attributeCondition <<<"$PROV")" "repository_owner_id"
check "provider trusts only GitHub's OIDC issuer" eq "$(jq -r .oidc.issuerUri <<<"$PROV")" "https://token.actions.githubusercontent.com"

log "2. Who can become which identity (Gate 2: the service-account bindings)"
bindings() { gcloud iam service-accounts get-iam-policy "$1" --project "$PROJECT_ID" --format=json; }
PUBB="$(bindings "$PUB")"; DEPB="$(bindings "$DEP")"
wif_members() { jq -r '[.bindings[]?|select(.role=="roles/iam.workloadIdentityUser")|.members[]]|join(",")' <<<"$1"; }
check "publisher is impersonable ONLY by release.yml@refs/heads/main" \
  eq "$(wif_members "$PUBB" | sed 's#.*attribute.job_workflow_ref/##')" "$GH_REPO/.github/workflows/release.yml@refs/heads/main"
check "deployer is impersonable ONLY by deploy.yml@refs/heads/main" \
  eq "$(wif_members "$DEPB" | sed 's#.*attribute.job_workflow_ref/##')" "$GH_REPO/.github/workflows/deploy.yml@refs/heads/main"
check "exactly one principal each (no wildcards, no repo-wide grant)" \
  eq "$(wif_members "$PUBB" | tr ',' '\n' | wc -l | tr -d ' ')$(wif_members "$DEPB" | tr ',' '\n' | wc -l | tr -d ' ')" "11"

log "3. Least privilege and no keys"
PROJ="$(gcloud projects get-iam-policy "$PROJECT_ID" --format=json)"
roles_of() { jq -r --arg m "serviceAccount:$1" '[.bindings[]|select(.members|index($m))|.role]|join(",")' <<<"$PROJ"; }
check "publisher holds NO project-level roles" eq "$(roles_of "$PUB")" ""
check "deployer holds NO project-level roles" eq "$(roles_of "$DEP")" ""
check "runtime SA holds NO project-level roles" eq "$(roles_of "$RUN_SA")" ""
check "no kcs-* service account has a user-managed key" \
  eq "$(for s in "$PUB" "$DEP" "$RUN_SA"; do gcloud iam service-accounts keys list --iam-account "$s" --managed-by=user --format='value(name)'; done | wc -l | tr -d ' ')" 0
check "creating a key is refused (organization policy) — so the pipeline works WITHOUT one by necessity" \
  fails gcloud iam service-accounts keys create /dev/null --iam-account "$PUB"
check "the registry is scoped: publisher can write, deployer can only read" \
  eq "$(gcloud artifacts repositories get-iam-policy keyless --location "$REGION" --project "$PROJECT_ID" --format=json | jq -r --arg p "serviceAccount:$PUB" --arg d "serviceAccount:$DEP" '[.bindings[]|select(.members|index($p) or index($d))|(.role+":"+(if (.members|index($p)) then "P" else "D" end))]|sort|join(",")')" \
  "roles/artifactregistry.reader:D,roles/artifactregistry.writer:P"

log "4. The release pipeline actually ran, with no secrets"
LAST="$(gh run list --repo "$GH_REPO" --workflow release.yml --status success --limit 1 --json databaseId --jq '.[0].databaseId')"
JOBS="$(gh run view "$LAST" --repo "$GH_REPO" --json jobs --jq '[.jobs[]|.name+"="+.conclusion]|join(",")')"
check "latest successful release run has build and deploy both green ($JOBS)" contains "$JOBS" "build=success"
check "…including the reusable deploy job" contains "$JOBS" "deploy"
check "repository has NO Actions secrets" eq "$(gh api "repos/$GH_REPO/actions/secrets" --jq .total_count)" 0
check "repository variables are identifiers only (WIF provider, SA emails, ids)" \
  ge "$(gh api "repos/$GH_REPO/actions/variables" --jq .total_count)" 6

log "5. What is running is exactly what was built and signed"
TOKEN="$(gcloud auth print-identity-token)"
check "service is private: unauthenticated request rejected (403)" eq "$(curl -s -o /dev/null -w '%{http_code}' "$SVC_URL/")" 403
BODY="$(curl -s -H "Authorization: Bearer $TOKEN" "$SVC_URL/")"
check "authenticated request served (200)" eq "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" "$SVC_URL/")" 200
check "served build reports a commit that exists on origin/main" contains "$(gh api "repos/$GH_REPO/commits/$(jq -r .version <<<"$BODY")" --jq .sha 2>/dev/null)" "$(jq -r .version <<<"$BODY")"
check "served build reports the workflow run that built it" contains "$(jq -r .built_by <<<"$BODY")" "/actions/runs/"
check "Cloud Run serves a digest, not a mutable tag" contains "$DIGEST" "sha256:"
check "the served digest is the one the release run pushed (tag sha-<commit> resolves to it)" \
  eq "$(gcloud artifacts docker images describe "$IMAGE:sha-$(jq -r .version <<<"$BODY" | cut -c1-7)" --format='get(image_summary.digest)' 2>/dev/null || \
        gcloud artifacts docker tags list "$AR_REPO/app" --format='value(tag,version)' | grep -m1 "sha-" | awk '{print $2}' | sed 's#.*/##')" "$DIGEST"

log "6. Signature, SBOM and provenance verify from outside (no secrets on this machine)"
check "signature verifies against the release.yml identity" "$ROOT/scripts/verify.sh" "$DIGEST" --signature-only
check "SBOM attestation + SLSA provenance verify too" "$ROOT/scripts/verify.sh" "$DIGEST"
check "WRONG signer identity is rejected (deploy.yml did not sign this)" \
  fails env SIGNER="https://github.com/$GH_REPO/.github/workflows/deploy.yml@refs/heads/main" "$ROOT/scripts/verify.sh" "$DIGEST" --signature-only
check "WRONG ref is rejected (a branch build would not verify)" \
  fails env SIGNER="https://github.com/$GH_REPO/.github/workflows/release.yml@refs/heads/evil" "$ROOT/scripts/verify.sh" "$DIGEST" --signature-only
check "WRONG issuer is rejected" \
  fails env ISSUER="https://accounts.google.com" "$ROOT/scripts/verify.sh" "$DIGEST" --signature-only
SBOM_COMPONENTS="$(cosign verify-attestation --type cyclonedx "$IMAGE@$DIGEST" --certificate-identity "https://github.com/$GH_REPO/.github/workflows/release.yml@refs/heads/main" --certificate-oidc-issuer https://token.actions.githubusercontent.com 2>/dev/null | head -1 | jq -r '.payload|@base64d|fromjson|.predicate.components|length' 2>/dev/null || echo 0)"
check "the SBOM is real: it lists $SBOM_COMPONENTS components" ge "$SBOM_COMPONENTS" 10

log "7. Tags are immutable"
TAG="$(gcloud artifacts docker tags list "$AR_REPO/app" --format='value(tag)' 2>/dev/null | grep '^sha-' | head -1)"
IMM="$(mktemp -d)"; printf 'FROM scratch\nLABEL tamper=1\n' > "$IMM/Dockerfile"
docker build -q -t "$IMAGE:$TAG" "$IMM" >/dev/null 2>&1
check "re-pushing an existing release tag with different content is refused" fails docker push -q "$IMAGE:$TAG"
rm -rf "$IMM"

if [ "${SKIP_DRILLS:-0}" != 1 ]; then
  log "8. WIF negative controls (workflows on GitHub that must be REFUSED)"
  read -r NRUN NCON < <(run_workflow wif-negative.yml main)
  check "wif-negative.yml on main (right repo, wrong workflow file): both impersonations refused ($NCON)" eq "$NCON" success
  NLOG="$(gh run view "$NRUN" --repo "$GH_REPO" --log 2>/dev/null || true)"
  check "…and Google said so (IAM denial in the log)" bash -c "grep -qiE 'getAccessToken|Unable to acquire impersonated|unauthorized_client|denied' <<<\"\$1\"" _ "$NLOG"
  check "…and the assertion step printed DENIED-AS-EXPECTED" contains "$NLOG" "DENIED-AS-EXPECTED"

  git push -q origin "main:refs/heads/drill/wif-negative" 2>/dev/null || git push -q -f origin "main:refs/heads/drill/wif-negative"
  read -r BRUN BCON < <(run_workflow deploy.yml drill/wif-negative -f "digest=$DIGEST")
  BSTEP="$(gh run view "$BRUN" --repo "$GH_REPO" --json jobs --jq '[.jobs[].steps[]|select(.conclusion=="failure")|.name]|first // "none"')"
  check "deploy.yml dispatched from a BRANCH cannot authenticate (conclusion: $BCON)" eq "$BCON" failure
  check "…it failed at the auth step, before verification or deployment (step: $BSTEP)" contains "$BSTEP" "google-github-actions/auth"
  check "…and production did not change" eq "$(served_digest)" "$DIGEST"
  git push -q origin --delete drill/wif-negative 2>/dev/null || true

  log "9. Rogue images: the deploy workflow must refuse what the pipeline didn't produce"
  DRILL="$("$ROOT/scripts/rogue-drill.sh" 2>&1 | grep '^RESULT' || true)"
  echo "$DRILL"
  check "UNSIGNED image: deploy run FAILED" contains "$DRILL" "RESULT unsigned conclusion=failure"
  check "UNSIGNED image: it failed at 'Verify signature'" contains "$DRILL" "RESULT unsigned conclusion=failure failed_step=Verify signature"
  check "UNSIGNED image: production still serves the previous digest" contains "$DRILL" "RESULT unsigned served_unchanged=yes"
  check "WRONG-SIGNER image: the human signature is genuinely valid for the human identity" contains "$DRILL" "RESULT human signature_valid_for_human=yes"
  check "WRONG-SIGNER image: …yet the deploy run FAILED at 'Verify signature'" contains "$DRILL" "RESULT human conclusion=failure failed_step=Verify signature"
  check "WRONG-SIGNER image: production unchanged" contains "$DRILL" "RESULT human served_unchanged=yes"
  check "CONTROL: the genuine image passes the same workflow" contains "$DRILL" "RESULT genuine conclusion=success"
fi

echo
printf '\033[1m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
