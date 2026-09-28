# 0001 — Two gates, and the second one pins the workflow *file* on `main`

**Status:** accepted

## Context
The common Workload Identity Federation setup trusts "any workflow in repo X". That makes every workflow file, every branch, and every pull request from a collaborator a path to production credentials.

## Decision
* **Gate 1 — the provider's attribute condition** accepts only tokens whose `repository_id` *and* `repository_owner_id` match. Numeric ids, not names: a renamed or deleted-and-recreated repository cannot inherit the trust.
* **Gate 2 — each service account's `workloadIdentityUser` binding** names one principal: `attribute.job_workflow_ref/<repo>/.github/workflows/<file>@refs/heads/main`. `release.yml` on `main` can become the *publisher*; `deploy.yml` on `main` can become the *deployer*; nothing else can become either.

`job_workflow_ref` is the file that contains the running job (for a reusable workflow, the **called** file). So `release.yml` calls `deploy.yml`, and the deploy job's token carries `deploy.yml@refs/heads/main`.

## Consequences
* A pull request, a feature branch, or any other workflow file in the same repository authenticates as nothing. This is asserted by two live drills ([test results](../test-results.md)): a workflow file that is not in the bindings is refused for both identities, and `deploy.yml` dispatched from a *branch* fails at the auth step.
* Adding a new workflow that needs cloud access is a Terraform change reviewed like any IAM change, not a YAML edit.
* Trade-off: the workflow *file name* becomes part of the security boundary; renaming `deploy.yml` breaks deploys until the binding is updated. That is the intended failure direction.
