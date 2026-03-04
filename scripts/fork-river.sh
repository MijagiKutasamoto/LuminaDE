#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/fork-river.sh <github-user-or-org>
# Example:
#   ./scripts/fork-river.sh my-org

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <github-user-or-org>"
  exit 1
fi

TARGET_OWNER="$1"
UPSTREAM_REPO="riverwm/river"
TARGET_REPO="${TARGET_OWNER}/river"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Run: gh auth login"
  exit 1
fi

echo "Forking ${UPSTREAM_REPO} -> ${TARGET_REPO}"
FORK_READY="false"
if gh api "users/${TARGET_OWNER}" >/dev/null 2>&1; then
  if gh repo fork "${UPSTREAM_REPO}" --clone=false --org "${TARGET_OWNER}"; then
    FORK_READY="true"
  fi
else
  if gh repo fork "${UPSTREAM_REPO}" --clone=false --owner "${TARGET_OWNER}"; then
    FORK_READY="true"
  fi
fi

echo "Cloning your fork"
if [[ ! -d vendor/river ]]; then
  mkdir -p vendor
  if [[ "$FORK_READY" == "true" ]]; then
    git clone "https://github.com/${TARGET_REPO}.git" vendor/river
  else
    echo "Fork API unavailable - cloning upstream only (read-only baseline)."
    git clone "https://github.com/${UPSTREAM_REPO}.git" vendor/river
  fi
fi

pushd vendor/river >/dev/null

if [[ "$FORK_READY" == "true" ]]; then
  git remote add upstream "https://github.com/${UPSTREAM_REPO}.git" 2>/dev/null || true
else
  git remote rename origin upstream 2>/dev/null || true
fi
git fetch upstream
git checkout main

echo "Done. Current remotes:"
git remote -v

popd >/dev/null

echo "River fork initialized at vendor/river"
