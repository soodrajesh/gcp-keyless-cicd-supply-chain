# 0003 — Deploy by digest; tags are immutable and unique per run

**Status:** accepted (the second half found by the first live run)

Cloud Run is always given `image@sha256:…`. The Artifact Registry repository has **immutable tags** (`docker_config.immutable_tags`), so a tag can never be silently repointed at different content — asserted live by trying to re-push an existing release tag with different content (refused).

Immutable tags have a side effect the first live run demonstrated: the push to `main` triggered a release, and the pipeline's own dispatched re-run of the *same commit* then failed with `cannot update tag … tag immutability`. Tags are therefore `build-<run number>-<short sha>`: unique per run, still human-readable. The digest, not the tag, is what identity and deployment refer to.
