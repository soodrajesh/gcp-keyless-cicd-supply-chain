#!/usr/bin/env bash
# Verify an image the way the deploy workflow does — from your own machine, with no secrets.
#   ./scripts/verify.sh sha256:<digest>            signature + SBOM attestation + SLSA provenance
#   SIGNER=<identity> ./scripts/verify.sh <digest> --signature-only     (used by the negative tests)
source "$(dirname "$0")/lib.sh"
need cosign; need gh
DIGEST="${1:?usage: verify.sh sha256:<digest> [--signature-only]}"
SIGNER="${SIGNER:-https://github.com/${GH_REPO}/.github/workflows/release.yml@refs/heads/main}"
ISSUER="${ISSUER:-https://token.actions.githubusercontent.com}"
REF="${IMAGE}@${DIGEST}"

cosign verify "$REF" --certificate-identity "$SIGNER" --certificate-oidc-issuer "$ISSUER" >/dev/null 2>&1 \
  && ok "signature: signed by $SIGNER" || { warn "signature check FAILED for $REF (expected signer $SIGNER)"; exit 1; }
[ "${2:-}" = "--signature-only" ] && exit 0
cosign verify-attestation --type cyclonedx "$REF" --certificate-identity "$SIGNER" --certificate-oidc-issuer "$ISSUER" >/dev/null 2>&1 \
  && ok "SBOM attestation (CycloneDX) verified" || { warn "SBOM attestation FAILED"; exit 1; }
gh attestation verify "oci://$REF" --repo "$GH_REPO" --signer-workflow "$GH_REPO/.github/workflows/release.yml" >/dev/null 2>&1 \
  && ok "SLSA build provenance verified (GitHub attestation)" || { warn "provenance FAILED"; exit 1; }
