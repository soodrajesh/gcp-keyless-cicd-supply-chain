# Live test results

Captured output of `./scripts/test.sh` against the live pipeline (project `claude-code-507112`, europe-west1, repo `soodrajesh/gcp-keyless-cicd-supply-chain`) on 2026-09-28: **42 passed, 0 failed**.

```
==> 1. Trust boundary configuration (Gate 1: the provider)
✔ provider accepts only this repository by immutable numeric id (1393481318)
✔ provider also pins the repository OWNER id
✔ provider trusts only GitHub's OIDC issuer
==> 2. Who can become which identity (Gate 2: the service-account bindings)
✔ publisher is impersonable ONLY by release.yml@refs/heads/main
✔ deployer is impersonable ONLY by deploy.yml@refs/heads/main
✔ exactly one principal each (no wildcards, no repo-wide grant)
==> 3. Least privilege and no keys
✔ publisher holds NO project-level roles
✔ deployer holds NO project-level roles
✔ runtime SA holds NO project-level roles
✔ no kcs-* service account has a user-managed key
✔ creating a key is refused (organization policy) — so the pipeline works WITHOUT one by necessity
✔ the registry is scoped: publisher can write, deployer can only read
==> 4. The release pipeline actually ran, with no secrets
✔ latest successful release run has build and deploy both green (build=success,deploy / deploy=success)
✔ …including the reusable deploy job
✔ repository has NO Actions secrets
✔ repository variables are identifiers only (WIF provider, SA emails, ids)
==> 5. What is running is exactly what was built and signed
✔ service is private: unauthenticated request rejected (403)
✔ authenticated request served (200)
✔ served build reports a commit that exists on origin/main
✔ served build reports the workflow run that built it
✔ Cloud Run serves a digest, not a mutable tag
✔ the served digest was pushed under a tag for this exact commit (build-<n>-7171044)
==> 6. Signature, SBOM and provenance verify from outside (no secrets on this machine)
✔ signature verifies against the release.yml identity
✔ SBOM attestation + SLSA provenance verify too
✔ WRONG signer identity is rejected (deploy.yml did not sign this)
✔ WRONG ref is rejected (a branch build would not verify)
✔ WRONG issuer is rejected
✔ the SBOM is real: it lists 116 components
==> 7. Tags are immutable
✔ re-pushing an existing release tag with different content is refused
==> 8. WIF negative controls (workflows on GitHub that must be REFUSED)
✔ wif-negative.yml on main (right repo, wrong workflow file): both impersonations refused (success)
✔ …and Google said so (IAM denial in the log)
✔ …and the assertion step printed DENIED-AS-EXPECTED
✔ deploy.yml dispatched from a BRANCH cannot authenticate (conclusion: failure)
✔ …it failed at the auth step, before verification or deployment (step: Run google-github-actions/auth@7c6bc770dae815cd3e89ee6cdf493a5fab2cc093)
✔ …and production still serves a genuinely signed image
==> 9. Rogue images: the deploy workflow must refuse what the pipeline didn't produce
✔ UNSIGNED image: deploy run FAILED
✔ UNSIGNED image: it failed at 'Verify signature'
✔ UNSIGNED image: the rogue digest was never served
✔ WRONG-SIGNER image: the signature is genuinely valid for the OTHER identity
✔ WRONG-SIGNER image: …yet the deploy run FAILED at 'Verify signature'
✔ WRONG-SIGNER image: the rogue digest was never served
✔ CONTROL: the genuine image passes the same workflow
42 passed, 0 failed
```

## What the first runs got wrong

Kept because they are the best evidence the checks are not vacuous — each was a real defect the live pipeline exposed, not a test-only issue:

| # | Found by | Defect | Fix |
|---|---|---|---|
| 1 | first `terraform apply` | WIF pool display name `GitHub Actions ($repo)` exceeded Google's 32-character limit | shortened to a fixed string |
| 2 | first release run | `deploy.yml` tried to self-impersonate its own already-impersonated identity to mint the smoke-test token | mint the ID token with the `auth` action directly (`token_format: id_token`) |
| 3 | second release run | Artifact Registry immutable tags: re-running the same commit tried to reuse `sha-<12-char-sha>` | tags are now `build-<run-number>-<short-sha>`, unique per run |
| 4 | `wif-negative.yml` drill | `google-github-actions/auth` without `token_format: access_token` only writes a credentials file — it never calls IAM, so "auth succeeded" proved nothing about authorization | added `token_format: access_token` to force the real exchange; the drill now genuinely fails as expected |
| 5 | the rogue-signer drill | signing "as a human" via Sigstore used the SAME Google identity as the operator running the drill, which is not a meaningfully different signer | sign as a different, unrelated service account (`kcs-runtime`) instead |
| 6 | the drills, run right after a `git push` | comparing the served digest to an exact pre-drill snapshot is falsely "changed" when an unrelated, legitimate release lands concurrently (which `git push` to `main` triggers) | assert the property that matters — the rogue digest was never served / production still serves a genuinely signed image — not byte-identical-to-before |
| 7 | test tooling | a tag-lookup test matched by commit-sha suffix alone, ambiguous when the same commit was built twice | match by exact digest instead |
