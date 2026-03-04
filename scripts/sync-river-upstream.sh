#!/usr/bin/env bash
set -euo pipefail

# Sync your river fork with upstream safely.
# Requires: vendor/river cloned via scripts/fork-river.sh

RIVER_DIR="vendor/river"

if [[ ! -d "${RIVER_DIR}" ]]; then
  echo "Missing ${RIVER_DIR}. Run scripts/fork-river.sh first."
  exit 1
fi

pushd "${RIVER_DIR}" >/dev/null

git fetch upstream

git checkout main
git merge --ff-only upstream/main

git push origin main

popd >/dev/null

echo "River fork synchronized with upstream/main"
