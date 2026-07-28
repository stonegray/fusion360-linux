#!/usr/bin/env bash
# helpers/worktree-task.sh — Create a git worktree for a subagent task
# Usage: bash helpers/worktree-task.sh <branch-name> [<based-on>]
#   Creates /tmp/f360-worktree-<branch-name>/ on the new branch
#   If based-on is given, creates branch from that ref
set -euo pipefail

NAME="${1:?usage: worktree-task.sh <branch-name> [<based-on>]}"
BASED_ON="${2:-dev}"
WORKTREE="/tmp/f360-worktree-$NAME"
REPO="$(cd "$(dirname "$0")/.." && pwd)"

# Clean any stale worktree
if [[ -d "$WORKTREE" ]]; then
  git worktree remove --force "$WORKTREE" 2>/dev/null || true
fi

# Create branch (force in case it exists from a prior run)
git branch -f "$NAME" "$BASED_ON" 2>/dev/null || git branch "$NAME" "$BASED_ON"

# Create worktree
git worktree add "$WORKTREE" "$NAME"

echo "$WORKTREE"
