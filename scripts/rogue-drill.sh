#!/usr/bin/env bash
# The supply-chain drill. Two images that reached the registry by ways the pipeline did not
# approve are pushed, and the DEPLOY workflow (on main, with real credentials) is asked to ship
# each one. It must refuse both, leave production untouched, and still ship the genuine image.
#   1. UNSIGNED         built and pushed from this laptop
#   2. WRONG SIGNER     validly signed via Sigstore — but as a human (Google identity), not the pipeline
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

log "Rogue 2: signed by a human identity via Sigstore, not by the pipeline"
D2="$(push_rogue "rogue-human-$STAMP" human)"; ok "pushed $D2"
TOKEN="$(gcloud auth print-identity-token --audiences=sigstore)"
cosign sign --yes --identity-token "$TOKEN" "$IMAGE@$D2" >/dev/null 2>&1 && ok "signed as $(gcloud config get-value account 2>/dev/null) (a real, valid Sigstore signature)"
SIGNER="$ADMIN_EMAIL" ISSUER="https://accounts.google.com" "$ROOT/scripts/verify.sh" "$D2" --signature-only >/dev/null 2>&1 \
  && echo "RESULT human signature_valid_for_human=yes" || echo "RESULT human signature_valid_for_human=NO"
attempt human "$D2"

log "Control: the genuine, pipeline-signed image is accepted by the same workflow"
attempt genuine "$GOOD"
