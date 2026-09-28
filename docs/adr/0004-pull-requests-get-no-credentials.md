# 0004 — Pull requests authenticate as nothing

`ci.yml` (pull requests and pushes) has `permissions: contents: read` and no `id-token`. It lints, tests, validates Terraform, scans, **builds the image and runs the vulnerability gate**, but pushes nothing and cannot obtain a Google token at all — including for pull requests from forks. Anything that needs cloud access lives in `release.yml`/`deploy.yml`, which run only on `main` (or by manual dispatch of a reviewed workflow) and are the only principals in the IAM bindings ([ADR 0001](0001-two-gates-pin-the-workflow-file.md)).

`scripts/check-pins.sh` (run in CI) fails the build if any third-party action is referenced by a mutable tag instead of a full commit SHA.
