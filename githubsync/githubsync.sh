#!/bin/bash

# githubsync.sh
# 
# 2025-06-08 20:44
#
# Usage: githubsync.sh <repo> <access> <local_path> [--log-dir <log_dir>] [--debug]
# Example: githubsync.sh 500Foods/Zoomer RW /fvl/git/500Foods/Zoomer --log-dir /fvl/git/logs --debug
# Syncs a local Git repo with GitHub, pulls remote changes, and pushes local changes (if RW).
# Reports zero pushes/pulls if no tracked or unignored files have changed.

# Default log directory and debug mode
LOG_DIR="$HOME/githubsync_logs"
DEBUG=false

# Parse arguments
REPO=""
ACCESS=""
LOCAL_PATH=""
while [ $# -gt 0 ]; do
    case "$1" in
        --log-dir)
            LOG_DIR="$2"
            shift 2
            ;;
        --debug)
            DEBUG=true
            shift
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
    echo "Usage: $0 <repo> <access> <local_path> [--log-dir <log_dir>] [--debug]" >&2
    exit 1
fi

# Validate access
if [ "$ACCESS" != "R" ] && [ "$ACCESS" != "RW" ]; then
    echo "Error: Access must be 'R' or 'RW'." >&2
    exit 1
fi

# Validate repo format
if ! [[ "$REPO" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$ ]]; then
    echo "Error: Invalid repo format. Expected 'owner/repo'." >&2
    exit 1
fi

GITHUB_URL="git@github.com:$REPO.git"
REPO_SAFE=$(echo "$REPO" | tr '/' '-')
LOGFILE="$LOG_DIR/githubsync_${REPO_SAFE}_$(date +%Y%m%d_%H%M%S).log"
START_TIME=$(date +%s)

# Create log directory
if ! mkdir -p "$LOG_DIR"; then
    echo "Error: Failed to create log directory $LOG_DIR." >&2
    exit 1
fi

# Log function (write to file, echo errors to console, and debug to both if enabled)
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" >> "$LOGFILE"
    if [[ "$1" == Error:* ]]; then
        echo "$message" >&2
    elif [ "$DEBUG" = true ]; then
        echo "$message"
    fi
}

# Log file list (write to file and console if debug)
log_file_list() {
    local prefix="$1"
    local files="$2"
    echo "$prefix" >> "$LOGFILE"
    if [ -n "$files" ]; then
        echo "$files" >> "$LOGFILE"
        if [ "$DEBUG" = true ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $prefix"
            echo "$files"
        fi
    fi
}

# Start SSH agent and ensure cleanup
log "Starting SSH agent."
eval "$(ssh-agent -s)" > /dev/null
trap 'ssh-agent -k > /dev/null; log "SSH agent stopped."' EXIT
if ! ssh-add ~/.ssh/id_rsa 2> /dev/null; then
    log "Error: Failed to add SSH key."
    exit 1
fi
log "SSH key added successfully."

# Create local directory
log "Creating local directory $(dirname "$LOCAL_PATH")."
if ! mkdir -p "$(dirname "$LOCAL_PATH")"; then
    log "Error: Failed to create directory $(dirname "$LOCAL_PATH")."
    exit 1
fi

# Track files
PULLED=0
PUSHED=0

# Check if local path is a git repo
log "Checking if $LOCAL_PATH is a Git repo."
if ! cd "$LOCAL_PATH" 2>/dev/null; then
    log "Cloning $REPO to $LOCAL_PATH."
    CLONE_OUTPUT=$(git clone "$GITHUB_URL" "$LOCAL_PATH" 2>&1)
    if [ $? -ne 0 ]; then
        log "Error: Failed to clone $REPO. Output: $CLONE_OUTPUT"
        exit 1
    fi
    log "Clone successful. Output: $CLONE_OUTPUT"
    cd "$LOCAL_PATH"
fi

# Log initial repo state
log "Current directory: $(pwd)"
log "Git status before sync:"
git status >> "$LOGFILE" 2>&1

# Check Git config for user identity
log "Checking Git user identity."
USER_NAME=$(git config --get user.name)
USER_EMAIL=$(git config --get user.email)
if [ -z "$USER_NAME" ] || [ -z "$USER_EMAIL" ]; then
    log "Error: Git user identity not configured. Run 'git config --global user.name \"Your Name\"' and 'git config --global user.email \"you@example.com\"' to set it."
    exit 1
fi
log "Git user name: $USER_NAME"
log "Git user email: $USER_EMAIL"

# Get main branch
log "Determining main branch."
MAIN_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
log "Main branch detected: $MAIN_BRANCH"
if ! git rev-parse --verify "origin/$MAIN_BRANCH" >/dev/null 2>&1; then
    log "Error: Remote branch $MAIN_BRANCH does not exist."
    exit 1
fi
log "Checking out branch $MAIN_BRANCH."
if ! git checkout "$MAIN_BRANCH" 2>/dev/null; then
    log "Branch $MAIN_BRANCH not found locally, creating it."
    if ! git checkout -b "$MAIN_BRANCH"; then
        log "Error: Failed to checkout or create branch $MAIN_BRANCH."
        exit 1
    fi
fi
log "Current branch: $(git rev-parse --abbrev-ref HEAD)"

# Check for local changes before pull (to preserve them)
log "Checking for local changes before pull (RW mode)."
MODIFIED=$(git diff --name-only | wc -l)
log "Modified tracked files count: $MODIFIED"
if [ "$MODIFIED" -gt 0 ]; then
    MODIFIED_FILES=$(git diff --name-only)
    log_file_list "Modified tracked files:" "$MODIFIED_FILES"
fi
STAGED=$(git diff --staged --name-only | wc -l)
log "Staged files count: $STAGED"
if [ "$STAGED" -gt 0 ]; then
    STAGED_FILES=$(git diff --staged --name-only)
    log_file_list "Staged files:" "$STAGED_FILES"
fi
UNTRACKED=$(git ls-files --others --exclude-standard | wc -l)
log "Untracked, unignored files count: $UNTRACKED"
if [ "$UNTRACKED" -gt 0 ]; then
    UNTRACKED_FILES=$(git ls-files --others --exclude-standard)
    log_file_list "Untracked, unignored files:" "$UNTRACKED_FILES"
fi
# Correct total changes to avoid double-counting
if [ "$MODIFIED" -gt 0 ] || [ "$STAGED" -gt 0 ] || [ "$UNTRACKED" -gt 0 ]; then
    TOTAL_CHANGES=1
else
    TOTAL_CHANGES=0
fi
log "Total changes detected before pull: $TOTAL_CHANGES"

# Stash changes early if they exist (for RW mode)
STASHED=false
if [ "$ACCESS" = "RW" ] && [ "$TOTAL_CHANGES" -gt 0 ]; then
    log "Attempting to stash local changes before pull."
    STASH_OUTPUT=$(git stash push --include-untracked -m "githubsync stash" 2>&1)
    if echo "$STASH_OUTPUT" | grep -q "No local changes to save"; then
        log "No changes to stash. Output: $STASH_OUTPUT"
        TOTAL_CHANGES=0
    else
        if ! git stash list | grep -q "githubsync stash"; then
            log "Error: Failed to create stash. Output: $STASH_OUTPUT"
            exit 1
        fi
        log "Stash created successfully. Stash list:"
        git stash list >> "$LOGFILE" 2>&1
        log "Stash content:"
        git stash show -p >> "$LOGFILE" 2>&1
        STASHED=true
    fi
fi

# Save current state for pull diff
log "Fetching from origin."
FETCH_OUTPUT=$(git fetch origin 2>&1)
if [ $? -ne 0 ]; then
    log "Error: Failed to fetch from origin. Output: $FETCH_OUTPUT"
    exit 1
fi
log "Fetch successful. Output: $FETCH_OUTPUT"
BEFORE_PULL=$(git rev-parse HEAD)
log "Commit hash before pull: $BEFORE_PULL"

# Pull remote changes (remote wins conflicts)
log "Pulling from $REPO."
PULL_OUTPUT=$(git reset --hard "origin/$MAIN_BRANCH" 2>&1)
if [ $? -ne 0 ]; then
    log "Error: Failed to reset to origin/$MAIN_BRANCH. Output: $PULL_OUTPUT"
    exit 1
fi
log "Pull successful. Output: $PULL_OUTPUT"

# Count pulled files
AFTER_PULL=$(git rev-parse HEAD)
log "Commit hash after pull: $AFTER_PULL"
if [ "$BEFORE_PULL" != "$AFTER_PULL" ]; then
    PULLED=$(git diff --name-only "$BEFORE_PULL" "$AFTER_PULL" | wc -l)
    log "Files pulled: $PULLED"
    log_file_list "Changed files from pull:" "$(git diff --name-only "$BEFORE_PULL" "$AFTER_PULL")"
else
    log "No changes pulled from remote."
fi

# For RW repos, apply stashed changes and push
if [ "$ACCESS" = "RW" ] && [ "$STASHED" = true ]; then
    log "Applying stashed changes."
    STASH_POP_OUTPUT=$(git stash pop 2>&1)
    if [ $? -ne 0 ]; then
        log "Error: Failed to apply stashed changes. Stash preserved. Output: $STASH_POP_OUTPUT"
        exit 1
    fi
    log "Stashed changes applied. Output: $STASH_POP_OUTPUT"
    # Recheck changes after stash apply
    MODIFIED=$(git diff --name-only | wc -l)
    log "Modified tracked files count after stash: $MODIFIED"
    if [ "$MODIFIED" -gt 0 ]; then
        log_file_list "Modified tracked files after stash:" "$(git diff --name-only)"
    fi
    STAGED=$(git diff --staged --name-only | wc -l)
    log "Staged files count after stash: $STAGED"
    if [ "$STAGED" -gt 0 ]; then
        log_file_list "Staged files after stash:" "$(git diff --staged --name-only)"
    fi
    UNTRACKED=$(git ls-files --others --exclude-standard | wc -l)
    log "Untracked, unignored files count after stash: $UNTRACKED"
    if [ "$UNTRACKED" -gt 0 ]; then
        log_file_list "Untracked, unignored files after stash:" "$(git ls-files --others --exclude-standard)"
    fi
    # Correct total changes
    if [ "$MODIFIED" -gt 0 ] || [ "$STAGED" -gt 0 ] || [ "$UNTRACKED" -gt 0 ]; then
        TOTAL_CHANGES=1
    else
        TOTAL_CHANGES=0
    fi
    log "Total changes detected after stash: $TOTAL_CHANGES"
    
    if [ "$TOTAL_CHANGES" -gt 0 ]; then
        # Save state before commit for push diff
        BEFORE_PUSH=$(git rev-parse HEAD)
        log "Commit hash before push: $BEFORE_PUSH"
        log "Staging all changes."
        STAGE_OUTPUT=$(git add . 2>&1)
        if [ $? -ne 0 ]; then
            log "Error: Failed to stage changes. Output: $STAGE_OUTPUT"
            exit 1
        fi
        log "Staging successful. Output: $STAGE_OUTPUT"
        log "Committing local changes."
        COMMIT_OUTPUT=$(git commit -m "githubsync: Auto-sync $(date)" 2>&1)
        if [ $? -ne 0 ]; then
            log "Error: Failed to commit changes. Output: $COMMIT_OUTPUT"
            exit 1
        fi
        log "Commit successful. Output: $COMMIT_OUTPUT"
        # Count pushed files
        AFTER_PUSH=$(git rev-parse HEAD)
        log "Commit hash after commit: $AFTER_PUSH"
        if [ "$BEFORE_PUSH" != "$AFTER_PUSH" ]; then
            PUSHED=$(git diff --name-only "$BEFORE_PUSH" "$AFTER_PUSH" | wc -l)
            log "Files pushed: $PUSHED"
            log_file_list "Changed files for push:" "$(git diff --name-only "$BEFORE_PUSH" "$AFTER_PUSH")"
        fi
        # Push to remote
        log "Pushing to $REPO."
        PUSH_OUTPUT=$(git push origin "$MAIN_BRANCH" 2>&1)
        if [ $? -ne 0 ]; then
            log "Error: Push failed. Output: $PUSH_OUTPUT"
            exit 1
        fi
        log "Push successful. Output: $PUSH_OUTPUT"
    else
        log "No tracked, staged, or unignored changes to commit after stash."
        PUSHED=0
    fi
else
    log "Read-only repo or no changes stashed, skipping push."
    PUSHED=0
fi

# Calculate elapsed time
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))

# Log final repo state
log "Git status after sync:"
git status >> "$LOGFILE" 2>&1

# Log and output summary
SUMMARY="$(date '+%Y-%m-%d %H:%M:%S') $REPO... Files Pushed: $PUSHED Files Pulled: $PULLED Result: Success ($ELAPSED_MIN:$(printf "%02d" $ELAPSED_SEC))"
log "$SUMMARY"
echo "$SUMMARY"

exit 0
