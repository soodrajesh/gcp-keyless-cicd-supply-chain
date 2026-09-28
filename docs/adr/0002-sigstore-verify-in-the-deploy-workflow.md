# 0002 — Keyless Sigstore signing, verified by the deploy workflow (not Binary Authorization)

**Status:** accepted, with a stated gap

## Context
The sibling repo `gcp-cloudrun-secure-delivery` enforces provenance with Binary Authorization and KMS-held attestor keys. This repo answers a different question: what if there are **no signing keys at all**?

## Decision
`release.yml` signs the image digest with `cosign sign` using the job's OIDC identity: Sigstore's Fulcio issues a short-lived certificate whose subject is `https://github.com/<repo>/.github/workflows/release.yml@refs/heads/main`, and the signature is recorded in the Rekor transparency log. It also attaches a CycloneDX SBOM as a signed attestation and a SLSA build-provenance attestation (`actions/attest-build-provenance`).

`deploy.yml` refuses to deploy a digest unless `cosign verify` (identity + issuer), `cosign verify-attestation` and `gh attestation verify` all pass. `scripts/verify.sh` runs the same three checks from any machine with no secrets.

## Why not Binary Authorization
Binary Authorization attestors are built on KMS or PGP keys, which is exactly the key management this repo removes. The signer's *identity* is the trust anchor here.

## The gap (stated, not hidden)
Enforcement lives in the workflow, not in the platform. A human or service with `roles/run.developer` on the service could deploy an unsigned image directly. Here that is limited to the deployer service account (only impersonable by `deploy.yml` on `main`) and the project owner. Closing it fully means admission control at the platform (Binary Authorization with an attestor that trusts this Sigstore identity, or restricting `run.developer` to the pipeline only). The drills prove the *pipeline* refuses rogue images, not that nothing else can deploy them.

## Consequences
* Verification is possible by anyone, offline of GitHub secrets: the certificate identity is public.
* Sigstore's public-good instance is used, so the repository is public and the signing metadata is public. Do not use this exact setup for a private repository without a private Sigstore deployment.
