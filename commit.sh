#!/bin/bash

set -e

# ================= Configuration =================
GIT_USER_NAME="Admin"                               # Specify your user name here
GIT_USER_EMAIL="admin@hakr.xyz"                     # Specify your email here
COMMIT_MSG="${1:-$(date -u '+%Y-%m-%d %H:%M:%S UTC')}"     # Commit message, defaults to "Auto Commit"
REMOTE_NAME="${2:-origin}"                          # Remote name, defaults to origin
GIT_GC="${GIT_GC:-1}"                               # Set to 0 to skip cleaning .git caches and unreachable objects after a successful push

# Check if the current directory is a valid git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[ERROR] Not a git repository. Please run this inside a valid git project."
  exit 1
fi

# Get the current branch name
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || true)
if [ -z "$CURRENT_BRANCH" ]; then
  CURRENT_BRANCH="main"
fi

# ================= Git LFS =================
use_lfs=0
if command -v git-lfs >/dev/null 2>&1; then
  git lfs install --local >/dev/null 2>&1 || true
  use_lfs=1
  export GIT_LFS_SKIP_SMUDGE=1
  echo "[INFO] Git LFS enabled (project-local). Local checkout keeps raw files."
else
  echo "[INFO] git-lfs not found; large files will be tracked as regular blobs."
fi

echo "[INFO] Staging all changes..."
git add -A

echo "[STEP] Creating an orphan branch to clear history..."
git branch -D temp_clean_branch 2>/dev/null || true
git checkout --orphan temp_clean_branch

echo "[STEP] Committing (using specified user, ignoring gitconfig)..."
git -c user.name="$GIT_USER_NAME" \
    -c user.email="$GIT_USER_EMAIL" \
    commit -m "$COMMIT_MSG"

echo "[STEP] Replacing the old branch locally..."
# Force-rename the temp branch over the old branch (single atomic step, so the
# old branch is never left in a half-deleted state if something fails).
git branch -M "$CURRENT_BRANCH"

cleanup_git() {
  echo "[STEP] Cleaning .git caches and large objects..."
  git reflog expire --expire=now --all 2>/dev/null || true
  git gc --prune=now --quiet || echo "[WARN] git gc failed"

  if command -v git-lfs >/dev/null 2>&1; then
    if git lfs prune --force 2>/dev/null; then
      echo "[INFO] Pruned local LFS cache."
    else
      echo "[INFO] No LFS cache to prune."
    fi
  fi
}

echo "[STEP] Force pushing to remote repository..."
# Force push is required because history has been rewritten
if ! git push -f "$REMOTE_NAME" "$CURRENT_BRANCH"; then
  echo "[ERROR] Force push failed. Remote history was NOT updated."
  exit 1
fi

if [ "$use_lfs" = "1" ]; then
  echo "[STEP] Uploading LFS objects..."
  if ! git lfs push --all "$REMOTE_NAME" "$CURRENT_BRANCH" 2>/dev/null; then
    echo "[ERROR] LFS object upload failed (check LFS storage quota on GitHub)."
    exit 1
  fi
  echo "[SUCCESS] LFS objects uploaded."
fi

echo "[SUCCESS] Done! Repository history has been cleared locally and pushed to remote."

if [ "$GIT_GC" = "1" ]; then
  cleanup_git
fi