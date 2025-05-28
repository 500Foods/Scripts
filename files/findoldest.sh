#!/bin/bash

# Usage info
usage() {
    echo "Usage: $0 [directory] [--before YYYYMMDD]"
    echo "  directory: Path to search (default: current directory)"
    echo "  --before YYYYMMDD: List all files before this date"
    exit 1
}

# Parse arguments
directory="."
before_date=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --before)
            shift
            if [[ ! $1 =~ ^[0-9]{8}$ ]]; then
                echo "Error: --before requires YYYYMMDD format"
                usage
            fi
            before_date="$1"
            shift
            ;;
        --help)
            usage
            ;;
        *)
            if [[ -d "$1" ]]; then
                directory="$1"
                shift
            else
                echo "Error: Invalid directory or option"
                usage
            fi
            ;;
    esac
done

# Convert directory to absolute path
directory=$(realpath "$directory" 2>/dev/null)
if [[ ! -d "$directory" ]]; then
    echo "Error: Directory '$directory' does not exist"
    exit 1
fi

# Count total files for progress indicator
total_files=$(find "$directory" -type f -readable -printf '\0' | wc -c)
if [[ "$total_files" -eq 0 ]]; then
    echo "No files found in $directory"
    exit 1
fi

# Function to convert YYYYMMDD to seconds since epoch
date_to_epoch() {
    local ymd=$1
    date -d "${ymd:0:4}-${ymd:4:2}-${ymd:6:2}" +%s 2>/dev/null || {
        echo "Error: Invalid date format for --before"
        exit 1
    }
}

# Function to format file details with aligned columns
format_file() {
    local file="$1"
    # Get all stat fields in one call
    local stat_output
    stat_output=$(stat -c '%A %h %U %G %s %Y' "$file" 2>/dev/null) || {
        printf "%-11s %2s %-8s %-8s %8s %s %s\n" "??????????" "?" "unknown" "unknown" "?" "????-??-?? ??:??:??" "$file"
        return
    }
    read -r perms links owner group size epoch <<< "$stat_output"
    # Convert epoch to timestamp
    local timestamp
    timestamp=$(date -d "@$epoch" "+%Y-%m-%d %H:%M:%S.%N %z" 2>/dev/null || echo "????-??-?? ??:??:??")
    # Format output with fixed-width columns
    printf "%-11s %2s %-8s %-8s %8s %s %s\n" "$perms" "$links" "$owner" "$group" "$size" "$timestamp" "$file"
}

# If --before is specified, list all files before that date
if [[ -n "$before_date" ]]; then
    cutoff_epoch=$(date_to_epoch "$before_date")
    file_count=0
    last_update=$SECONDS
    last_file_count=0
    files_per_sec=0
    find "$directory" -type f -readable -printf '%T@\0%p\0' | while IFS= read -r -d $'\0' epoch; do
        read -r -d $'\0' file
        ((file_count++))
        if (( SECONDS > last_update )); then
            files_per_sec=$(( file_count - last_file_count ))
            eta=$(( total_files > file_count ? (total_files - file_count) / (files_per_sec > 0 ? files_per_sec : 1) : 0 ))
            percent=$(( (file_count * 100) / total_files ))
            printf "\rSearching %d of %d files (%d%% complete, %d files/sec, ETA: %d seconds)     " \
                "$file_count" "$total_files" "$percent" "$files_per_sec" "$eta"
            last_update=$SECONDS
            last_file_count="$file_count"
        fi
        if (( ${epoch%.*} < cutoff_epoch )); then
            printf "\r%${COLUMNS:-80}s\r" " " # Clear line
            format_file "$file"
        fi
    done
    printf "\r%${COLUMNS:-80}s\r" " " # Clear progress line
    exit 0
fi

# Find the oldest file(s) with progress indicator
find "$directory" -type f -readable -printf '%T@\0%p\0' | {
    oldest_time=""
    declare -A oldest_files
    file_count=0
    last_update=$SECONDS
    last_file_count=0
    files_per_sec=0
    while IFS= read -r -d $'\0' epoch; do
        read -r -d $'\0' file
        ((file_count++))
        if (( SECONDS > last_update )); then
            files_per_sec=$(( file_count - last_file_count ))
            eta=$(( total_files > file_count ? (total_files - file_count) / (files_per_sec > 0 ? files_per_sec : 1) : 0 ))
            percent=$(( (file_count * 100) / total_files ))
            printf "\rSearching %d of %d files (%d%% complete, %d files/sec, ETA: %d seconds)     " \
                "$file_count" "$total_files" "$percent" "$files_per_sec" "$eta"
            last_update=$SECONDS
            last_file_count="$file_count"
        fi
        epoch_int=${epoch%.*} # Integer part of epoch
        if [[ -z "$oldest_time" || epoch_int -lt ${oldest_time%.*} ]]; then
            oldest_time="$epoch"
            unset oldest_files
            declare -A oldest_files
            oldest_files["$file"]=1
        elif [[ "$epoch_int" -eq "${oldest_time%.*}" && "$(echo "$epoch == $oldest_time" | bc -l)" -eq 1 ]]; then
            oldest_files["$file"]=1
        fi
    done
    printf "\r%${COLUMNS:-80}s\r" " " # Clear progress line
    if [[ -z "$oldest_time" ]]; then
        echo "No files found in $directory"
        exit 0
    fi
    for file in "${!oldest_files[@]}"; do
        format_file "$file"
    done
}
