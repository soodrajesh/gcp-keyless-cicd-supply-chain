#!/usr/bin/env bash
# Fail if any workflow uses a third-party action by mutable tag instead of a full commit SHA.
# Local reusable workflows (./.github/...) are exempt: they are this repo.
set -euo pipefail
cd "$(dirname "$0")/.."
bad="$(grep -rnE '^\s*(-\s*)?uses:\s' .github/workflows | grep -vE 'uses:\s+\./' | grep -vE '@[0-9a-f]{40}(\s|$)' || true)"
if [ -n "$bad" ]; then
  echo "actions not pinned to a full commit SHA:"; echo "$bad"; exit 1
fi
echo "all third-party actions are pinned to commit SHAs"
