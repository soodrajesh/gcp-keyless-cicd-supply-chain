# Threat model

| Threat | Control | Proven by |
|---|---|---|
| A stolen long-lived cloud key | There is no key: OIDC token → STS → short-lived access token. The organization also forbids key creation. | test §3 (no user-managed keys; creating one is refused) |
| A pull request / fork gains cloud access | Gate 1 (repo id) + Gate 2 (workflow file on `main`); `ci.yml` has no `id-token` | test §2, §8 |
| A workflow on a branch, or another file in the repo, deploys | Only `deploy.yml@refs/heads/main` is bound to the deployer | test §8: branch-dispatched deploy fails at the auth step; `wif-negative.yml` is refused for both identities |
| A repo renamed/deleted/recreated inherits trust | Provider pins numeric `repository_id` and `repository_owner_id` | test §1 |
| An unsigned image reaches the registry and is deployed | Deploy verifies signature + SBOM + provenance before deploying | test §9: unsigned image refused at *Verify signature*, production unchanged |
| An image validly signed by the wrong identity is deployed | Verification pins the exact certificate identity and issuer | test §9: an image signed via Sigstore by a different identity is genuinely valid for that identity and is still refused |
| A tag is repointed at different content | Immutable tags; deploy by digest | test §7 |
| A vulnerable base image ships | Trivy gate (CRITICAL, fixable) runs *before* push | `release.yml` |
| A malicious/hijacked third-party action | Pinned to commit SHAs; CI enforces it | `scripts/check-pins.sh` |
| Injection through the `digest` input | Passed via `env`, validated against `^sha256:[0-9a-f]{64}$` before use, never interpolated into a script | `deploy.yml` |

## Not covered (stated)
* **Someone with `roles/run.developer` or project owner can still deploy directly** — see [ADR 0002](adr/0002-sigstore-verify-in-the-deploy-workflow.md).
* **A compromised `main`.** Anyone who can merge to `main` can change `release.yml` itself. Branch protection and required reviews are repository settings, not something this repo can prove; they are the real control here.
* **A vulnerability with no fix yet** passes the gate by design (`ignore-unfixed`).
* **No "outsider repository" drill**: proving that a *different* repository is rejected by Gate 1 needs a second repository and the delete permission to clean it up, which this token lacks. Gate 1 is asserted by reading the provider's condition, not by an attack.
