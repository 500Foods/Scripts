#!/bin/bash

# sync_all.sh
# Usage: sync_all.sh <repo_list_file>
# Example: sync_all.sh ~/repos.txt
# Runs github-sync.sh for all repos in the specified repo list, logs, and emails HTML summary

# Configuration
GITHUBSYNC_PATH="/fvl/git/scr/github-sync.sh"  # Path to githubsync.sh
EMAIL="willard@500foods.com"                    # Email address for summary
LOG_DIR="/fvl/git/log"                          # Log directory
MUTT_CMD="mutt"                                  # Mutt command

# Convert days to human-readable format (e.g., 10y4m26d)
days_to_human() {
    local days=$1
    if [ "$days" -eq 0 ]; then
        echo "0d"
        return
    fi
    local years=$((days / 365))
    local days_left=$((days % 365))
    local months=$((days_left / 30))
    local remaining_days=$((days_left % 30))
    local result=""
    [ "$years" -gt 0 ] && result="${years}y"
    [ "$months" -gt 0 ] && result="${result}${months}m"
    result="${result}${remaining_days}d"
    [ -z "$result" ] && result="0d"
    echo "$result"
}

# Check arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 <repo_list_file>" >&2
    exit 1
fi

REPO_LIST="$1"
LOGFILE="$LOG_DIR/sync_all_$(date +%Y%m%d_%H%M%S).log"
SUMMARY_FILE=$(mktemp)
HTML_FILE=$(mktemp)
START_TIME=$(date +%s)
START_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
ANY_FAILED=0
REPO_COUNT=0
PUSH_COUNT=0
PULL_COUNT=0
TOTAL_SIZE_MB=0
MAX_AGE=0
MIN_ACTIVITY=999999  # Large initial value for finding minimum

# Validate repo list file
if [ ! -f "$REPO_LIST" ] || [ ! -r "$REPO_LIST" ]; then
    echo "Error: Repo list file '$REPO_LIST' does not exist or is not readable." >&2
    exit 1
fi

# Validate githubsync path
if [ ! -x "$GITHUBSYNC_PATH" ]; then
    echo "Error: github-sync.sh at '$GITHUBSYNC_PATH' does not exist or is not executable." >&2
    exit 1
fi

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

# Create log directory
mkdir -p "$LOG_DIR" || {
    log "Error: Failed to create log directory $LOG_DIR."
    exit 1
}

# Start summary
log "Starting sync_all with $REPO_LIST"
echo "$START_TIMESTAMP Start" >> "$SUMMARY_FILE"

# Set locale for thousands separators
export LC_NUMERIC=C

# Current epoch time for age/activity calculations (May 25, 2025)
CURRENT_EPOCH=$(date +%s)

# Read repo list
while read -r repo access path; do
    # Skip empty lines or comments
    [[ -z "$repo" || "$repo" =~ ^# ]] && continue
    ((REPO_COUNT++))
    log "Syncing $repo ($access) to $path"
    # Measure per-repo duration (start)
    REPO_START_TIME=$(date +%s)
    # Run githubsync, capture summary (preserve console output)
    OUTPUT=$("$GITHUBSYNC_PATH" "$repo" "$access" "$path" --log-dir "$LOG_DIR" 2>> "$LOGFILE" | tee /dev/tty)
    # Parse output for pushes, pulls, and result
    PUSHES=$(echo "$OUTPUT" | grep -oP 'Files Pushed: \K\d+' || echo "0")
    PULLS=$(echo "$OUTPUT" | grep -oP 'Files Pulled: \K\d+' || echo "0")
    RESULT=$(echo "$OUTPUT" | grep -oP 'Result: \K\w+' || echo "Failed")
    # Format pushes and pulls with thousands separators
    PUSHES_FORMATTED=$(printf "%'d" "$PUSHES")
    PULLS_FORMATTED=$(printf "%'d" "$PULLS")
    # Check for failure
    if [ "$RESULT" != "Success" ]; then
        ANY_FAILED=1
    fi
    ((PUSH_COUNT += PUSHES))
    ((PULL_COUNT += PULLS))
    # Calculate repo size in MB
    if [ -d "$path" ]; then
        BYTES=$(du -sb "$path" | cut -f1)
        SIZE_MB=$(echo "scale=1; $BYTES / 1000000" | bc)
        TOTAL_SIZE_MB=$(echo "scale=1; $TOTAL_SIZE_MB + $SIZE_MB" | bc)
        SIZE_FORMATTED=$(printf "%.1f" "$SIZE_MB" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')
    else
        SIZE_FORMATTED="0.0"
        log "Warning: Path $path does not exist for size calculation."
    fi
    # Calculate Age (days since oldest file) and Activity (days since newest file), excluding .git
    if [ -d "$path" ]; then
        # Check for .project_start for Age
        if [ -f "$path/.project_start" ]; then
            OLDEST_EPOCH=$(stat -c %Y "$path/.project_start" 2>/dev/null)
        else
            OLDEST_EPOCH=$(find "$path" -type f -not -path "*/.git/*" -not -name ".project_start" -exec stat -c %Y {} + 2>/dev/null | sort -n | head -n 1)
        fi
        # Find newest file modification time, excluding .git and .project_start
        NEWEST_EPOCH=$(find "$path" -type f -not -path "*/.git/*" -not -name ".project_start" -exec stat -c %Y {} + 2>/dev/null | sort -nr | head -n 1)
        if [ -n "$OLDEST_EPOCH" ] && [ -n "$NEWEST_EPOCH" ]; then
            AGE_SECONDS=$((CURRENT_EPOCH - OLDEST_EPOCH))
            ACTIVITY_SECONDS=$((CURRENT_EPOCH - NEWEST_EPOCH))
            AGE_DAYS=$((AGE_SECONDS / (60 * 60 * 24)))
            ACTIVITY_DAYS=$((ACTIVITY_SECONDS / (60 * 60 * 24)))
            # Track maximum Age and minimum Activity
            if [ "$AGE_DAYS" -gt "$MAX_AGE" ]; then
                MAX_AGE=$AGE_DAYS
            fi
            if [ "$ACTIVITY_DAYS" -lt "$MIN_ACTIVITY" ]; then
                MIN_ACTIVITY=$ACTIVITY_DAYS
            fi
        else
            AGE_DAYS=0
            ACTIVITY_DAYS=0
            log "Warning: No files found in $path (excluding .git and .project_start) for age/activity calculation."
        fi
    else
        AGE_DAYS=0
        ACTIVITY_DAYS=0
        log "Warning: Path $path does not exist for age/activity calculation."
    fi
    # Convert age and activity to human-readable format
    AGE_FORMATTED=$(days_to_human "$AGE_DAYS")
    ACTIVITY_FORMATTED=$(days_to_human "$ACTIVITY_DAYS")
    # Calculate repo duration (end) - include size, age, and activity calculations
    REPO_END_TIME=$(date +%s)
    REPO_ELAPSED=$((REPO_END_TIME - REPO_START_TIME))
    REPO_MIN=$((REPO_ELAPSED / 60))
    REPO_SEC=$((REPO_ELAPSED % 60))
    REPO_DURATION="$REPO_MIN:$(printf "%02d" $REPO_SEC)"
    # Store repo details for HTML table
    echo "$START_TIMESTAMP|$AGE_FORMATTED|$ACTIVITY_FORMATTED|$repo|$access|$path|$SIZE_FORMATTED|$PUSHES_FORMATTED|$PULLS_FORMATTED|$REPO_DURATION|$RESULT" >> "$SUMMARY_FILE"
done < "$REPO_LIST"

# Complete summary
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))
DURATION="$ELAPSED_MIN:$(printf "%02d" $ELAPSED_SEC)"
echo "$(date '+%Y-%m-%d %H:%M:%S') Complete ($DURATION)" >> "$SUMMARY_FILE"
log "Sync_all completed"

# Determine status
if [ "$ANY_FAILED" -eq 0 ]; then
    STATUS="Success"
else
    STATUS="FAILURE"
fi

# Format totals
MAX_AGE_FORMATTED=$(days_to_human "$MAX_AGE")
MIN_ACTIVITY_FORMATTED=$(days_to_human "$MIN_ACTIVITY")
PUSH_COUNT_FORMATTED=$(printf "%'d" "$PUSH_COUNT")
PULL_COUNT_FORMATTED=$(printf "%'d" "$PULL_COUNT")
TOTAL_SIZE_FORMATTED=$(printf "%.1f" "$TOTAL_SIZE_MB" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')

# Generate HTML email with inlined zebra striping
cat << EOF > "$HTML_FILE"
<!DOCTYPE html>
<html>
<head>
    <style>
        table { border-collapse: collapse; width: auto; font-family: Arial, sans-serif; font-size: 12px; }
        th, td { padding: 0 5px; text-align: left; line-height: 1.2; }
        th.right, td.right { text-align: right; }
        th { background-color: #f2f2f2; }
        a { text-decoration: none; color: inherit; }
        .preamble, .postamble { margin: 15px 0; font-family: Arial, sans-serif; font-size: 12px; }
    </style>
</head>
<body>
    <div class="preamble">
        <h2>GitHub Sync Summary</h2>
        <p>This table contains the results of the repository synchronization process started at $START_TIMESTAMP.</p>
    </div>
    <table>
        <tr>
            <th>Timestamp</th>
            <th class="right">Age</th>
            <th class="right">Activity</th>
            <th>Repository</th>
            <th>Access</th>
            <th>Path</th>
            <th class="right">Size (MB)</th>
            <th class="right">Pushed</th>
            <th class="right">Pulled</th>
            <th>Duration</th>
            <th>Result</th>
        </tr>
EOF

# Add table rows with conditional highlighting for non-zero Pushed or Pulled, and zebra striping
ROW_NUM=0
while IFS='|' read -r timestamp age activity repo access path size pushes pulls duration result; do
    # Only process lines with valid repo data
    if [[ -n "$repo" ]]; then
        ((ROW_NUM++))
        # Remove any formatting from pushes and pulls for numeric comparison
        PUSHES_NUM=$(echo "$pushes" | sed 's/[^0-9]//g')
        PULLS_NUM=$(echo "$pulls" | sed 's/[^0-9]//g')
        # Check if Pushed or Pulled is non-zero for highlighting
        if [ "$PUSHES_NUM" -gt 0 ] || [ "$PULLS_NUM" -gt 0 ]; then
            echo "        <tr style=\"background-color: #fffde7;\"><td>$timestamp</td><td class=\"right\">$age</td><td class=\"right\">$activity</td><td><a href=\"https://github.com/$repo\">$repo</a></td><td>$access</td><td>$path</td><td class=\"right\">$size</td><td class=\"right\">$pushes</td><td class=\"right\">$pulls</td><td>$duration</td><td>$result</td></tr>" >> "$HTML_FILE"
        else
            # Apply zebra striping inline (every 4th row) for rows without activity
            if [ $((ROW_NUM % 4)) -eq 0 ]; then
                echo "        <tr style=\"background-color: #f0f0f0;\"><td>$timestamp</td><td class=\"right\">$age</td><td class=\"right\">$activity</td><td><a href=\"https://github.com/$repo\">$repo</a></td><td>$access</td><td>$path</td><td class=\"right\">$size</td><td class=\"right\">$pushes</td><td class=\"right\">$pulls</td><td>$duration</td><td>$result</td></tr>" >> "$HTML_FILE"
            else
                echo "        <tr><td>$timestamp</td><td class=\"right\">$age</td><td class=\"right\">$activity</td><td><a href=\"https://github.com/$repo\">$repo</a></td><td>$access</td><td>$path</td><td class=\"right\">$size</td><td class=\"right\">$pushes</td><td class=\"right\">$pulls</td><td>$duration</td><td>$result</td></tr>" >> "$HTML_FILE"
            fi
        fi
    fi
done < "$SUMMARY_FILE"

# Add summary row with total duration
cat << EOF >> "$HTML_FILE"
        <tr style="font-weight: bold; background-color: #ffffff;">
            <td>Total</td>
            <td class="right">$MAX_AGE_FORMATTED</td>
            <td class="right">$MIN_ACTIVITY_FORMATTED</td>
            <td>$REPO_COUNT</td>
            <td></td>
            <td></td>
            <td class="right">$TOTAL_SIZE_FORMATTED</td>
            <td class="right">$PUSH_COUNT_FORMATTED</td>
            <td class="right">$PULL_COUNT_FORMATTED</td>
            <td>$DURATION</td>
            <td></td>
        </tr>
    </table>
    <div class="postamble">
        <p><strong>Sync Completed:</strong> $(date '+%Y-%m-%d %H:%M:%S')</p>
    </div>
</body>
</html>
EOF

# Send HTML email via mutt
SUBJECT="GitHub Sync Summary $START_TIMESTAMP - $STATUS - $DURATION"
"$MUTT_CMD" -e "set content_type=text/html" -s "$SUBJECT" "$EMAIL" < "$HTML_FILE" || log "Error: Failed to send email."

# Append summary to log
cat "$SUMMARY_FILE" >> "$LOGFILE"

# Clean up
rm "$SUMMARY_FILE" "$HTML_FILE"
exit 0
