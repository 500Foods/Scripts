#!/bin/bash
#
# cephalopod.sh - Intelligent backup system for Ceph filesystems
# 
# DESCRIPTION:
#   Creates complete, standalone backup copies of a source filesystem (typically slow Ceph)
#   to fast local storage. Each backup is a full snapshot with no dependency chains.
#   Features real-time progress reporting, adaptive performance learning, and Home Assistant
#   integration for remote monitoring.
#
# USAGE:
#   cephalopod.sh [OPTIONS] /source/path /destination/path
#
# CHANGE HISTORY:
#   0.003 - Added advanced UI with dual scrolling panes, color support, and --lines option
#   0.002 - Added parameter parsing, help display, source/dest confirmation
#   0.001 - Initial version: display name and version number

VERSION="0.003"
SCRIPT_NAME="Cephalopod"

# UI Configuration
LOG_LINES=10  # Default number of log lines per pane
UI_ACTIVE=false
UI_DRAW_ROW=0
PATH_WIDTH=12  # Minimum width for path fields
INDENT_WIDTH=10  # Indentation for title/eta lines

# Terminal dimensions
term_width=0
term_height=0
ui_height=0

# Ensure UTF-8 support
export LC_ALL=en_US.UTF-8

# Define base colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 190)
WHITE=$(tput setaf 7)
BLACK=$(tput setaf 0)
BG_RED=$(tput setab 1)
BG_BLACK=$(tput setab 0)
RESET=$(tput sgr0)
BOLD=$(tput bold)

# Theme colors
COLOR_LINES=$RED
COLOR_LABELS=$GREEN
COLOR_VALUES=$WHITE
COLOR_TITLES=$YELLOW

# UI State
declare -a SOURCE_LOGS=()
declare -a TARGET_LOGS=()
TITLE_TEXT="$SCRIPT_NAME   Version $VERSION Release $(date +%Y-%m-%d)"
SOURCE_HEADER=""
TARGET_HEADER=""
STATUS_HEADER=""
STATUS_STATE="INITIALIZING"
ETA_TEXT="Elapsed Time 00:00:00   ETR 00:00:00   ETA: 2025-01-01 00:00:00"

# Display help information
show_help() {
    echo "$SCRIPT_NAME   Version $VERSION Release $(date +%Y-%m-%d)"
    echo ""
    echo "USAGE"
    echo "  $0 [OPTIONS] <source_path> <target_path>"
    echo ""
    echo "DESCRIPTION"
    echo "  Creates complete backup copies of source filesystem to destination."
    echo "  Each backup is a full snapshot with real-time progress reporting."
    echo ""
    echo "OPTIONS"
    echo "  -h, --help           Show this help message"
    echo "  -l, --lines NUMBER   Number of log lines to display (3-25, default: 10)"
    echo ""
    echo "EXAMPLES"
    echo "  $0 /mnt/ceph/data /backup/storage"
    echo "  $0 --lines 15 /mnt/ceph/data /backup/storage"
    echo ""
}

# Parse and validate command line arguments
parse_arguments() {
    local args=()
    
    # Process options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--lines)
                shift
                if [[ ! $1 =~ ^[0-9]+$ ]] || [[ $1 -lt 3 ]] || [[ $1 -gt 25 ]]; then
                    echo "ERROR: --lines must be a number between 3 and 25"
                    exit 1
                fi
                LOG_LINES=$1
                shift
                ;;
            -*)
                echo "ERROR: Unknown option: $1"
                echo ""
                show_help
                exit 1
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done
    
    # Check remaining arguments
    if [[ ${#args[@]} -ne 2 ]]; then
        echo "ERROR: Exactly two parameters required (source and target)"
        echo ""
        show_help
        exit 1
    fi
    
    # Set global variables
    SOURCE_PATH="${args[0]}"
    TARGET_PATH="${args[1]}"
    
    # Calculate path field width
    local src_len=${#SOURCE_PATH}
    local tgt_len=${#TARGET_PATH}
    PATH_WIDTH=$((src_len > tgt_len ? src_len : tgt_len))
    PATH_WIDTH=$((PATH_WIDTH < 12 ? 12 : PATH_WIDTH))
}

# Format number with commas and fixed width
format_number() {
    local num=$1
    local width=${2:-11}  # Default width for 99,999,999
    printf "%'${width}d" $num
}

# Format file/folder counts with colors
format_counts() {
    local files=$1
    local folders=$2
    printf "${COLOR_VALUES}%s${COLOR_LABELS} files   ${COLOR_VALUES}%s${COLOR_LABELS} folders${RESET}" \
        "$(format_number $files 11)" \
        "$(format_number $folders 11)"
}

# Format size with smart units
format_size() {
    local bytes=$1
    local size=$bytes
    local unit="B"
    
    # Convert to appropriate unit
    if [[ $size -gt 999 ]]; then
        size=$((size / 1024))
        unit="K"
    fi
    if [[ $size -gt 999 ]]; then
        size=$((size / 1024))
        unit="M"
    fi
    if [[ $size -gt 999 ]]; then
        size=$((size / 1024))
        unit="G"
    fi
    if [[ $size -gt 999 ]]; then
        size=$((size / 1024))
        unit="T"
    fi
    
    # Format with leading zeros and decimal
    local whole=$((size))
    local decimal=0
    if [[ $unit != "B" ]]; then
        # Calculate decimal part (rough approximation)
        decimal=$(( (bytes * 10 / (1024 ** ($(echo "BKMGT" | grep -b -o "$unit" | cut -d: -f1))) ) % 10 ))
    fi
    
    printf "${COLOR_VALUES}%03d.%d ${COLOR_LABELS}%s${RESET}" $whole $decimal $unit
}

# Initialize UI system
init_ui() {
    # Get terminal dimensions
    term_width=$(tput cols)
    term_height=$(tput lines)
    
    # Calculate total UI height
    # Title(1) + connector(1) + Source header(1) + Source logs + 
    # Target header(1) + Target logs + Status header(1) + connector(1) + ETA(1)
    ui_height=$((1 + 1 + 1 + LOG_LINES + 1 + LOG_LINES + 1 + 1 + 1))
    
    # Query cursor position to find command's row
    stty -echo  # Hide response
    printf "\033[6n"  # Query cursor position
    read -s -d R pos  # Read response
    stty echo
    
    # Extract row
    start_row=$(echo "$pos" | sed -n 's/.*\[\([0-9]*\);.*/\1/p')
    if [ -z "$start_row" ] || [ "$start_row" -ge "$term_height" ]; then
        # Fallback
        start_row=$((term_height - ui_height - 1))
        if [ "$start_row" -lt 0 ]; then
            start_row=0
        fi
    fi
    
    # Calculate lines available below cursor
    remaining_height=$((term_height - start_row - 1))
    
    # Always scroll by UI height
    scroll_lines=$((ui_height))
    for i in $(seq 1 $scroll_lines); do
        printf "\n"
    done
    
    # Recheck terminal height after scrolling
    term_height=$(tput lines)
    
    # Determine draw position
    if [ $remaining_height -ge $ui_height ]; then
        # Enough space initially
        UI_DRAW_ROW=$((start_row - 1))
        if [ $UI_DRAW_ROW -lt 0 ]; then
            UI_DRAW_ROW=0
        fi
    else
        # Position at bottom after scrolling
        UI_DRAW_ROW=$((term_height - ui_height))
        if [ $UI_DRAW_ROW -lt 0 ]; then
            UI_DRAW_ROW=0
        fi
    fi
    
    # Initialize log arrays
    for ((i=0; i<LOG_LINES; i++)); do
        SOURCE_LOGS[$i]=""
        TARGET_LOGS[$i]=""
    done
    
    # Hide cursor
    tput civis
    
    # Suppress ^C output
    stty -echoctl 2>/dev/null || true
    
    # Set up signal handlers
    trap cleanup_ui EXIT INT TERM
    trap handle_resize SIGWINCH
    
    UI_ACTIVE=true
}

# Draw title line with indentation
draw_title() {
    local row=$UI_DRAW_ROW
    local version_text="$VERSION"
    local date_text=$(date +%Y-%m-%d)
    local content="${COLOR_TITLES}$SCRIPT_NAME${COLOR_LABELS}   Version ${COLOR_VALUES}${version_text}${COLOR_LABELS} Released ${COLOR_VALUES}${date_text}"
    
    # Calculate visible length
    local visible_len=$((${#SCRIPT_NAME} + 11 + ${#version_text} + 10 + ${#date_text}))
    local total_width=$((term_width - (2 * INDENT_WIDTH)))  # Account for indentation on both sides
    local remaining=$((total_width - visible_len - 6))  # 6 for ╭─┤ and ├─╮
    local left_pad=$((remaining / 2))
    local right_pad=$((remaining - left_pad))
    
    tput cup $row 0
    printf "%*s" $INDENT_WIDTH ""  # Left indent
    printf "${COLOR_LINES}╭"
    printf '─%.0s' $(seq 1 $left_pad)
    printf "┤ ${content} ${COLOR_LINES}├"
    printf '─%.0s' $(seq 1 $right_pad)
    printf "╮${RESET}"
}

# Draw vertical connector
draw_connector() {
    local row=$1
    tput cup $row 0
    printf "%*s${COLOR_LINES}│%*s│${RESET}" $INDENT_WIDTH "" $((term_width - INDENT_WIDTH - INDENT_WIDTH - 2)) ""
}

# Draw header line with proper centering
draw_header() {
    local row=$1
    local text="$2"
    local line_type=$3

    # Calculate visible width from components (as before)
    local visible_len
    if [[ $line_type == "first" ]]; then
        visible_len=$((7 + PATH_WIDTH + 2 + 37 + 2 + 7))
    elif [[ $line_type == "last" ]]; then
        visible_len=$((7 + PATH_WIDTH + 2 + 37 + 2 + 7))
    else
        visible_len=$((7 + PATH_WIDTH + 2 + 37 + 2 + 7))
    fi

    tput cup $row 0

    if [[ $line_type == "first" ]]; then
        # Structure: ╭ + dashes + ┴ + dashes + ┤ + SPACE + content + SPACE + ├ + dashes + ┴ + dashes + ╮
        # Fixed chars: ╭(1) + ┴(1) + ┤(1) + space(1) + space(1) + ├(1) + ┴(1) + ╮(1) + 2*(INDENT_WIDTH-1) dashes
        # = 8 + 2*(INDENT_WIDTH-1) = 6 + 2*INDENT_WIDTH
        local fixed_chars=$((6 + 2 * INDENT_WIDTH))
        local available_padding=$((term_width - visible_len - fixed_chars))
	local left_pad=$((available_padding / 2 - 1))
        local right_pad=$((available_padding - left_pad - 2))

        # Ensure we don't exceed terminal width
        if [[ $((fixed_chars + visible_len + left_pad + right_pad)) -gt $term_width ]]; then
            right_pad=$((term_width - fixed_chars - visible_len - left_pad ))
        fi

        printf "${COLOR_LINES}╭"
        printf '─%.0s' $(seq 1 $((INDENT_WIDTH - 1)))
        printf "┴"
        printf '─%.0s' $(seq 1 $left_pad)
        printf "┤ ${text} ${COLOR_LINES}├"
        printf '─%.0s' $(seq 1 $right_pad)
        printf "┴"
        printf '─%.0s' $(seq 1 $((INDENT_WIDTH - 1)))
        printf "╮${RESET}"

    elif [[ $line_type == "last" ]]; then
        local fixed_chars=$((6 + 2 * INDENT_WIDTH))
        local available_padding=$((term_width - visible_len - fixed_chars))
        local left_pad=$((available_padding / 2 - 1))
        local right_pad=$((available_padding - left_pad - 2))

        if [[ $((fixed_chars + visible_len + left_pad + right_pad)) -gt $term_width ]]; then
            right_pad=$((term_width - fixed_chars - visible_len - left_pad))
        fi

        printf "${COLOR_LINES}╰"
        printf '─%.0s' $(seq 1 $((INDENT_WIDTH - 1)))
        printf "┬"
        printf '─%.0s' $(seq 1 $left_pad)
        printf "┤ ${text} ${COLOR_LINES}├"
        printf '─%.0s' $(seq 1 $right_pad)
        printf "┬"
        printf '─%.0s' $(seq 1 $((INDENT_WIDTH - 1)))
        printf "╯${RESET}"

    else
        # Middle header: ├ + dashes + ┤ + SPACE + content + SPACE + ├ + dashes + ┤
        # Fixed chars: ├(1) + ┤(1) + space(1) + space(1) + ├(1) + ┤(1) = 6
        local fixed_chars=6
        local available_padding=$((term_width - visible_len - fixed_chars))
        local left_pad=$((available_padding / 2 - 1))
        local right_pad=$((available_padding - left_pad - 2))

        if [[ $((fixed_chars + visible_len + left_pad + right_pad)) -gt $term_width ]]; then
            right_pad=$((term_width - fixed_chars - visible_len - left_pad))
        fi

        printf "${COLOR_LINES}├"
        printf '─%.0s' $(seq 1 $left_pad)
        printf "┤ ${text} ${COLOR_LINES}├"
        printf '─%.0s' $(seq 1 $right_pad)
        printf "┤${RESET}"
    fi
}

# Draw log line
draw_log_line() {
    local row=$1
    local text="$2"
    tput cup $row 0
    printf "${COLOR_LINES}│ %-*s ${COLOR_LINES}│${RESET}" $((term_width - 4)) "$text"
}

draw_eta() {
    local row=$((UI_DRAW_ROW + ui_height - 1))
    local elapsed="${1:-00:00:00}"
    local remaining="${2:-00:00:00}"
    local eta="${3:-2025-01-01 00:00:00}"
    local content="${COLOR_LABELS}Elapsed Time ${COLOR_VALUES}${elapsed}${COLOR_LABELS}   ETR ${COLOR_VALUES}${remaining}${COLOR_LABELS}   ETA ${COLOR_VALUES}${eta}"

    # Calculate visible length of content (without ANSI codes)
    local content_text="Elapsed Time ${elapsed}   ETR ${remaining}   ETA ${eta}"
    local visible_len=${#content_text}

    local total_width=$((term_width - (2 * INDENT_WIDTH)))  # Same as title line
    local remaining_space=$((total_width - visible_len - 6))  # 6 for ╰─┤ and ├─╯
    local left_pad=$((remaining_space / 2))
    local right_pad=$((remaining_space - left_pad))

    tput cup $row 0
    printf "%*s" $INDENT_WIDTH ""  # Left indent
    printf "${COLOR_LINES}╰"
    printf '─%.0s' $(seq 1 $left_pad)
    printf "┤ ${content} ${COLOR_LINES}├"
    printf '─%.0s' $(seq 1 $right_pad)
    printf "╯${RESET}"
}

# Update entire UI
update_ui() {
    local row=$UI_DRAW_ROW
    
    # Title line
    draw_title
    ((row++))
    
    # Vertical connector
    draw_connector $row
    ((row++))
    
    # Source header (first header)
    draw_header $row "$SOURCE_HEADER" "first"
    ((row++))
    
    # Source logs
    for ((i=0; i<LOG_LINES; i++)); do
        draw_log_line $row "${SOURCE_LOGS[$i]}"
        ((row++))
    done
    
    # Target header
    draw_header $row "$TARGET_HEADER" "middle"
    ((row++))
    
    # Target logs
    for ((i=0; i<LOG_LINES; i++)); do
        draw_log_line $row "${TARGET_LOGS[$i]}"
        ((row++))
    done
    
    # Status header (last header)
    draw_header $row "$STATUS_HEADER" "last"
    ((row++))
    
    # Vertical connector
    draw_connector $row
    ((row++))
    
    # ETA line
    draw_eta
    
    # Park cursor below UI
    tput cup $((UI_DRAW_ROW + ui_height)) 0
}

# Update source header
update_source_header() {
    local folders="${1:-0}"
    local files="${2:-0}"
    local size_bytes="${3:-0}"
    SOURCE_HEADER="${COLOR_LABELS}SOURCE${RESET} $(printf "%-${PATH_WIDTH}s" "$SOURCE_PATH")  $(format_counts $files $folders)  $(format_size $size_bytes)"
    [[ $UI_ACTIVE == true ]] && update_ui
}

# Update target header
update_target_header() {
    local folders="${1:-0}"
    local files="${2:-0}"
    local size_bytes="${3:-0}"
    TARGET_HEADER="${COLOR_LABELS}TARGET${RESET} $(printf "%-${PATH_WIDTH}s" "$TARGET_PATH")  $(format_counts $files $folders)  $(format_size $size_bytes)"
    [[ $UI_ACTIVE == true ]] && update_ui
}

# Update status header
update_status_header() {
    local folders="${1:-0}"
    local files="${2:-0}"
    local size_bytes="${3:-0}"
    STATUS_HEADER="${COLOR_LABELS}STATUS${RESET} $(printf "%-${PATH_WIDTH}s" "$STATUS_STATE")  $(format_counts $files $folders)  $(format_size $size_bytes)"
    [[ $UI_ACTIVE == true ]] && update_ui
}

# Update status state
update_status_state() {
    STATUS_STATE="$1"
    update_ui
}

# Update ETA line
update_eta_line() {
    local elapsed="${1:-00:00:00}"
    local remaining="${2:-00:00:00}"
    local eta="${3:-2025-01-01 00:00:00}"
    [[ $UI_ACTIVE == true ]] && draw_eta "$elapsed" "$remaining" "$eta"
}

# Log to source window
log_src() {
    local message="$1"
    # Shift array up
    for ((i=0; i<LOG_LINES-1; i++)); do
        SOURCE_LOGS[$i]="${SOURCE_LOGS[$((i+1))]}"
    done
    SOURCE_LOGS[$((LOG_LINES-1))]="$(date +%H:%M:%S) $message"
    [[ $UI_ACTIVE == true ]] && update_ui
}

# Log to target window
log_tgt() {
    local message="$1"
    # Shift array up
    for ((i=0; i<LOG_LINES-1; i++)); do
        TARGET_LOGS[$i]="${TARGET_LOGS[$((i+1))]}"
    done
    TARGET_LOGS[$((LOG_LINES-1))]="$(date +%H:%M:%S) $message"
    [[ $UI_ACTIVE == true ]] && update_ui
}

# Handle terminal resize
handle_resize() {
    term_width=$(tput cols)
    term_height=$(tput lines)
    [[ $UI_ACTIVE == true ]] && update_ui
}

# Clean up UI on exit
cleanup_ui() {
    if [[ $UI_ACTIVE == true ]]; then
        # Show cursor
        tput cnorm
        
        # Restore terminal settings
        stty echoctl 2>/dev/null || true
        
        # Move cursor below UI
        tput cup $((UI_DRAW_ROW + ui_height)) 0
        
        UI_ACTIVE=false
    fi
}

# Main execution function
main() {
    parse_arguments "$@"
    
    # Initialize the UI
    init_ui
    
    # Set initial content with INITIALIZING state
    update_source_header 0 0 0
    update_target_header 0 0 0  
    update_status_header 0 0 0
    update_eta_line
    
    # Draw initial UI
    update_ui
    
    # Demo the scrolling logs with state changes
    sleep 1
    log_src "Starting backup process..."
    log_tgt "Checking target..."
    
    sleep 1
    update_status_state "SCANNING"
    
    local size=1024
    for i in {1..10}; do
        log_src "Source operation $i: Scanning files..."
        log_tgt "Target check $i: Verifying space..."
        size=$((size * 3))
        update_source_header $((i * 10)) $((i * 100)) $size
        update_target_header $((i * 5)) $((i * 50)) $((size / 2))
        update_status_header $((i * 15)) $((i * 150)) $((size + size/2))
        
        if [[ $i -eq 10 ]]; then
            update_status_state "COPYING"
        fi
        
        sleep 0.5
    done
    
    update_status_state "CLEANING"
    sleep 2
}

# Execute main function with all arguments
main "$@"
