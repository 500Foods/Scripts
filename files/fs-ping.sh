#!/bin/bash

# fs-ping.sh - Filesystem ping utility
# Tests filesystem performance by writing, reading, and deleting files

usage() {
    echo "Usage: $0 [-n count] <directory>"
    echo "  -n count    Number of ping attempts (default: unlimited)"
    echo "  directory   Target directory to test"
    exit 1
}

# Default values
COUNT=-1
DIRECTORY=""

# Parse command line arguments
while getopts "n:" opt; do
    case $opt in
        n)
            COUNT=$OPTARG
            if ! [[ "$COUNT" =~ ^[0-9]+$ ]]; then
                echo "Error: -n requires a numeric argument"
                exit 1
            fi
            ;;
        \?)
            echo "Invalid option: -$OPTARG"
            usage
            ;;
    esac
done

shift $((OPTIND-1))

# Check if directory is provided
if [ $# -eq 0 ]; then
    echo "Error: Directory not specified"
    usage
fi

DIRECTORY="$1"

# Check if directory exists and is writable
if [ ! -d "$DIRECTORY" ]; then
    echo "Error: Directory '$DIRECTORY' does not exist"
    exit 1
fi

if [ ! -w "$DIRECTORY" ]; then
    echo "Error: Directory '$DIRECTORY' is not writable"
    exit 1
fi

# Function to generate random 16-character filename
generate_filename() {
    echo "$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1).tmp"
}

# Function to create 1MB of data
create_test_data() {
    dd if=/dev/zero bs=1024 count=1024 2>/dev/null
}

# Cleanup function for Ctrl+C
cleanup() {
    echo
    echo "--- Filesystem ping statistics ---"
    if [ $attempt_count -gt 0 ]; then
        echo "$attempt_count files transmitted"
        if [ $success_count -gt 0 ]; then
            avg_time=$((total_time / success_count))
            echo "Average time: ${avg_time}ms"
        fi
    fi
    exit 0
}

trap cleanup SIGINT

# Initialize counters
attempt_count=0
success_count=0
total_time=0

echo "FS-PING $DIRECTORY"

# Main ping loop
while [ $COUNT -eq -1 ] || [ $attempt_count -lt $COUNT ]; do
    filename=$(generate_filename)
    filepath="$DIRECTORY/$filename"
    
    # Start timing
    start_time=$(date +%s%3N)
    
    # Write 1MB file
    if ! create_test_data > "$filepath" 2>/dev/null; then
        echo "Error: Failed to write file $filename"
        ((attempt_count++))
        continue
    fi
    
    # Read the file back
    if ! cat "$filepath" > /dev/null 2>&1; then
        echo "Error: Failed to read file $filename"
        rm -f "$filepath" 2>/dev/null
        ((attempt_count++))
        continue
    fi
    
    # Delete the file
    if ! rm "$filepath" 2>/dev/null; then
        echo "Warning: Failed to delete file $filename"
    fi
    
    # End timing
    end_time=$(date +%s%3N)
    elapsed=$((end_time - start_time))
    
    # Update counters
    ((attempt_count++))
    ((success_count++))
    total_time=$((total_time + elapsed))
    
    # Output result
    echo "1048576 bytes from $filename: time=${elapsed}ms"
    
    # Sleep for 1 second between attempts (like ping)
    sleep 1
done

# Final statistics
echo
echo "--- Filesystem ping statistics ---"
echo "$attempt_count files transmitted, $success_count received"
if [ $success_count -gt 0 ]; then
    avg_time=$((total_time / success_count))
    echo "Average time: ${avg_time}ms"
fi
