#!/usr/bin/env bash
# scripts/deploy.sh — push main and keep cloudflare/workers-autoconfig in
# step with it in one step.
#
# Cloudflare's bot manages cloudflare/workers-autoconfig and can force-push
# it at any time, so this always resets the local copy to whatever origin
# currently has before merging main in, rather than trusting a local copy
# that may be stale.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Tracked files have uncommitted changes — commit or stash them first." >&2
  exit 1
fi

current_branch="$(git branch --show-current)"
if [[ "$current_branch" != "main" ]]; then
  echo "Must be on main to deploy (currently on $current_branch)." >&2
  exit 1
fi

echo "==> Fetching origin..."
git fetch origin

echo "==> Syncing main..."
git pull --rebase origin main
git push origin main

echo "==> Syncing cloudflare/workers-autoconfig..."
git checkout cloudflare/workers-autoconfig
git reset --hard origin/cloudflare/workers-autoconfig
git merge main --no-edit
git push origin cloudflare/workers-autoconfig

git checkout main
echo "==> Done. main and cloudflare/workers-autoconfig are both in sync with origin."
