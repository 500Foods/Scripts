#!/bin/bash

# githubsync.sh
# Usage: githubsync.sh <repo> <access> <local_path> [--log-dir <log_dir>]
# Example: githubsync.sh 500Foods/Zoomer RW /fvl/git/500Foods/Zoomer --log-dir /fvl/git/logs

set -e

# Default log directory
LOG_DIR="$HOME/githubsync_logs"

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --log-dir)
            LOG_DIR="$2"
            shift 2
            ;;
        *)
            if [ -z "$REPO" ]; then
                REPO="$1"
            elif [ -z "$ACCESS" ]; then
                ACCESS="$1"
            elif [ -z "$LOCAL_PATH" ]; then
                LOCAL_PATH="$1"
            else
                echo "Error: Too many arguments." >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# Check arguments
if [ -z "$REPO" ] || [ -z "$ACCESS" ] || [ -z "$LOCAL_PATH" ]; then
    echo "Usage: $0 <repo> <access> <local_path> [--log-dir <log_dir>]" >&2
    exit 1
fi

# Validate access
if [ "$ACCESS" != "R" ] && [ "$ACCESS" != "RW" ]; then
    echo "Error: Access must be 'R' or 'RW'." >&2
    exit 1
fi

GITHUB_URL="git@github.com:$REPO.git"
# Create log filename with repo name (replace / with -)
REPO_SAFE=$(echo "$REPO" | tr '/' '-')
LOGFILE="$LOG_DIR/githubsync_${REPO_SAFE}_$(date +%Y%m%d_%H%M%S).log"
START_TIME=$(date +%s)

# Validate repo format
if ! [[ "$REPO" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$ ]]; then
    echo "Error: Invalid repo format. Expected 'owner/repo'." >&2
    exit 1
fi

# Create log directory
mkdir -p "$LOG_DIR" || {
    echo "Error: Failed to create log directory $LOG_DIR." >&2
    exit 1
}

# Log function (write to file only)
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
}

# Start SSH agent
eval "$(ssh-agent -s)" > /dev/null
ssh-add ~/.ssh/id_rsa 2> /dev/null || {
    log "Error: Failed to add SSH key."
    exit 1
}

# Create local directory
mkdir -p "$(dirname "$LOCAL_PATH")" || {
    log "Error: Failed to create directory $(dirname "$LOCAL_PATH")."
    exit 1
}

# Track files
PULLED=0
PUSHED=0

# Check if local path is a git repo
if [ -d "$LOCAL_PATH/.git" ]; then
    log "Existing repo at $LOCAL_PATH."
    cd "$LOCAL_PATH"
else
    log "Cloning $REPO to $LOCAL_PATH."
    git clone "$GITHUB_URL" "$LOCAL_PATH" || {
        log "Error: Failed to clone $REPO."
        exit 1
    }
    cd "$LOCAL_PATH"
fi

# Get main branch
MAIN_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
if git rev-parse --verify "$MAIN_BRANCH" > /dev/null 2>&1; then
    git checkout "$MAIN_BRANCH"
else
    git checkout -b "$MAIN_BRANCH"
fi

# Save current state for pull diff
git fetch origin
BEFORE_PULL=$(git rev-parse HEAD)

# Stash local changes (only for RW repos)
STASHED=false
if [ "$ACCESS" = "RW" ] && [ -n "$(git status --porcelain)" ]; then
    log "Stashing local changes."
    git stash push -m "githubsync stash" > /dev/null 2>&1 || {
        log "Error: Failed to stash changes."
        exit 1
    }
    STASHED=true
    # Count stashed files
    PUSHED=$(git stash show --name-only | grep -v '^$' | wc -l)
fi

# Pull remote changes (remote wins conflicts)
log "Pulling from $REPO."
git reset --hard "origin/$MAIN_BRANCH" || {
    log "Error: Failed to reset to origin/$MAIN_BRANCH."
    exit 1
}

# Count pulled files
AFTER_PULL=$(git rev-parse HEAD)
if [ "$BEFORE_PULL" != "$AFTER_PULL" ]; then
    PULLED=$(git diff --name-only "$BEFORE_PULL" "$AFTER_PULL" | wc -l)
fi

# Apply stashed changes (only for RW repos)
if [ "$STASHED" = true ]; then
    log "Applying stashed changes."
    git stash pop > /dev/null 2>&1 || {
        log "Error: Failed to apply stashed changes. Stash preserved."
        exit 1
    }
    # Stage and commit
    log "Committing local changes."
    git add .
    git commit -m "githubsync: Auto-sync $(date)" > /dev/null 2>&1 || log "Nothing to commit."
else
    log "No local changes to commit."
fi

# Push to remote (only for RW repos)
if [ "$ACCESS" = "RW" ]; then
    log "Pushing to $REPO."
    git push origin "$MAIN_BRANCH" || {
        log "Error: Push failed."
        exit 1
    }
else
    log "Read-only repo, skipping push."
    PUSHED=0
fi

# Calculate elapsed time
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))

# Log and output summary
SUMMARY="$(date '+%Y-%m-%d %H:%M:%S') $REPO... Files Pushed: $PUSHED Files Pulled: $PULLED Result: Success ($ELAPSED_MIN:$(printf "%02d" $ELAPSED_SEC))"
log "$SUMMARY"
echo "$SUMMARY"

exit 0
