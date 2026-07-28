#!/usr/bin/env bash
# helpers/merge-task.sh — Merge a worktree branch back into dev
# Usage: bash helpers/merge-task.sh <branch-name>
set -euo pipefail

NAME="${1:?usage: merge-task.sh <branch-name>}"
WORKTREE="/tmp/f360-worktree-$NAME"

cd "$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! -d "$WORKTREE" ]]; then
  echo "Worktree $WORKTREE not found. Nothing to merge."
  exit 1
fi

# Fetch latest changes from the worktree branch
git fetch . "refs/heads/$NAME:refs/heads/$NAME" 2>/dev/null || true

# Check if there are commits to merge
COMMITS=$(git rev-list --count "origin/dev..$NAME" 2>/dev/null || echo "0")
if [[ "$COMMITS" -eq 0 ]]; then
  echo "No new commits on $NAME to merge."
else
  echo "Merging $COMMITS commit(s) from $NAME into dev..."
  git merge --no-edit "$NAME" -m "Merge $NAME: $(git log "$NAME" --oneline --max-count=1 --format='%s' 2>/dev/null || echo 'worktree task')"
fi

# Clean up
git worktree remove --force "$WORKTREE" 2>/dev/null || true
git branch -D "$NAME" 2>/dev/null || true
echo "Merged and cleaned up $NAME."
