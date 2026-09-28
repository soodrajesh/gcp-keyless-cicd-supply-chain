#!/usr/bin/env bash
# The supply-chain drill. Two images that reached the registry by ways the pipeline did not
# approve are pushed, and the DEPLOY workflow (on main, with real credentials) is asked to ship
# each one. It must refuse both, leave production untouched, and still ship the genuine image.
#   1. UNSIGNED         built and pushed from this laptop
#   2. WRONG SIGNER     validly signed via Sigstore — but by a different identity (kcs-runtime), not the pipeline
# Prints one result line per stage; test.sh asserts on them.
source "$(dirname "$0")/lib.sh"
need docker; need cosign; need gh; need gcloud
GOOD="$(served_digest)"
WORK="$ROOT/.test-tmp"; mkdir -p "$WORK"

push_rogue() { # <tag> <marker> -> digest on stdout
  local tag="$1" marker="$2" ctx; ctx="$(mktemp -d)"
  cp -R "$ROOT/app" "$ROOT/Dockerfile" "$ctx/"
  echo "# $marker $(date +%s)" >> "$ctx/app/main.py"   # different content => different digest
  docker build -q --build-arg GIT_SHA="$marker" -t "$IMAGE:$tag" "$ctx" >/dev/null
  docker push -q "$IMAGE:$tag" >/dev/null
  docker inspect --format '{{index .RepoDigests 0}}' "$IMAGE:$tag" | cut -d@ -f2
  rm -rf "$ctx"
}

attempt() { # <label> <digest> ; prints RESULT lines
  local label="$1" digest="$2" run conclusion failed_step
  read -r run conclusion < <(run_workflow deploy.yml main -f "digest=$digest")
  failed_step="$(gh run view "$run" --repo "$GH_REPO" --json jobs --jq '[.jobs[].steps[]|select(.conclusion=="failure")|.name]|first // "none"')"
  echo "RESULT $label conclusion=$conclusion failed_step=$failed_step run=$run"
  echo "RESULT $label served_unchanged=$([ "$(served_digest)" = "$GOOD" ] && echo yes || echo NO)"
}

log "Rogue 1: unsigned image pushed from this machine"
STAMP="$(date +%H%M%S)"
D1="$(push_rogue "rogue-unsigned-$STAMP" unsigned)"; ok "pushed $D1"
attempt unsigned "$D1"

log "Rogue 2: validly signed via Sigstore, but by a different identity than the pipeline"
OTHER="kcs-runtime@${PROJECT_ID}.iam.gserviceaccount.com"
D2="$(push_rogue "rogue-otheridentity-$STAMP" otheridentity)"; ok "pushed $D2"
TOKEN="$(gcloud auth print-identity-token --impersonate-service-account="$OTHER" --audiences=sigstore --include-email 2>/dev/null)"
cosign sign --yes --identity-token "$TOKEN" "$IMAGE@$D2" >/dev/null 2>&1 && ok "signed as $OTHER (a real, valid Sigstore signature)"
SIGNER="$OTHER" ISSUER="https://accounts.google.com" "$ROOT/scripts/verify.sh" "$D2" --signature-only >/dev/null 2>&1 \
  && echo "RESULT other signature_valid_for_that_identity=yes" || echo "RESULT other signature_valid_for_that_identity=NO"
attempt other "$D2"

log "Control: the genuine, pipeline-signed image is accepted by the same workflow"
attempt genuine "$GOOD"
