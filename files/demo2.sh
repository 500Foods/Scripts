#!/bin/bash

# Function to display help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

A terminal UI demo that displays two scrolling sections with customizable height.

OPTIONS:
    -l, --lines NUM     Set the number of lines for each section (default: 8)
    -h, --help          Show this help message and exit

DESCRIPTION:
    This script creates a terminal UI with two sections that display scrolling
    content. Both sections will have the same height as specified by the --lines
    parameter. The UI automatically adjusts to terminal resizing and positions
    itself appropriately based on available space.

EXAMPLES:
    $0                  # Run with default 8 lines per section
    $0 -l 5             # Run with 5 lines per section
    $0 --lines 12       # Run with 12 lines per section

EOF
}

# Default values
lines_per_section=8

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--lines)
            if [[ -n $2 && $2 =~ ^[0-9]+$ ]]; then
                lines_per_section=$2
                shift 2
            else
                echo "Error: --lines requires a positive integer argument" >&2
                exit 1
            fi
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Error: Unknown option '$1'" >&2
            echo "Use -h or --help for usage information." >&2
            exit 1
            ;;
    esac
done

# Validate lines_per_section
if [[ $lines_per_section -lt 1 ]]; then
    echo "Error: Number of lines must be at least 1" >&2
    exit 1
fi

# Ensure UTF-8 support for box-drawing characters (e.g., ╭, ╮)
export LC_ALL=en_US.UTF-8

# Define terminal-independent colors using tput
RED=$(tput setaf 1)    # Red for UI borders
YELLOW=$(tput setaf 3) # Yellow for content text
RESET=$(tput sgr0)     # Reset attributes

# Get initial terminal dimensions
term_width=$(tput cols)
term_height=$(tput lines)

# Query cursor position to find command's row
stty -echo  # Hide response
printf "\033[6n"  # Query cursor position
read -s -d R pos  # Read response
stty echo
# Extract row (0-based, e.g., 4 for last line in 5-line terminal)
start_row=$(echo "$pos" | sed -n 's/.*\[\([0-9]*\);.*/\1/p')
if [ -z "$start_row" ] || [ "$start_row" -ge "$term_height" ]; then
  # Fallback: Assume cursor near bottom, leave room for UI
  start_row=$((term_height - ui_height - 1))
  if [ "$start_row" -lt 0 ]; then
    start_row=0
  fi
fi

# Define UI structure using the parameterized line count
top_lines_count=$lines_per_section
bottom_lines_count=$lines_per_section
ui_height=$((1 + top_lines_count + 1 + bottom_lines_count + 1 + 1))  # top border + top content + middle border + bottom content + bottom border + spacing

# Calculate lines available *below* cursor
remaining_height=$((term_height - start_row - 1))

# Set UI width
box_width=$term_width
inner_width=$((box_width - 2))

# Draw UI rectangles
draw_rectangles() {
  tput cup $draw_row 0
  printf "${RED}╭%*s╮${RESET}" $((box_width - 2)) "$(printf '─%.0s' $(seq 1 $((box_width - 2))))"
  
  # Draw top section
  for row in $(seq 1 $top_lines_count); do
    tput cup $((draw_row + row)) 0
    printf "${RED}│%*s│${RESET}" $inner_width ""
  done
  
  # Draw middle separator
  tput cup $((draw_row + top_lines_count + 1)) 0
  printf "${RED}├%*s┤${RESET}" $((box_width - 2)) "$(printf '─%.0s' $(seq 1 $((box_width - 2))))"
  
  # Draw bottom section
  for row in $(seq $((top_lines_count + 2)) $((top_lines_count + 1 + bottom_lines_count))); do
    tput cup $((draw_row + row)) 0
    printf "${RED}│%*s│${RESET}" $inner_width ""
  done
  
  # Draw bottom border
  tput cup $((draw_row + top_lines_count + 1 + bottom_lines_count + 1)) 0
  printf "${RED}╰%*s╯${RESET}" $((box_width - 2)) "$(printf '─%.0s' $(seq 1 $((box_width - 2))))"
}

# Update content in rectangles
update_content() {
  local base_row=$1
  local lines=("${@:2}")
  for i in $(seq 0 $((lines_per_section - 1))); do
    tput cup $((base_row + i)) 1
    printf "${YELLOW}%-${inner_width}.${inner_width}s${RESET}" "${lines[i]}"
  done
}

# Handle terminal resize
handle_resize() {
  term_width=$(tput cols)
  term_height=$(tput lines)
  box_width=$term_width
  inner_width=$((box_width - 2))
  draw_rectangles
  for row in $(seq $((draw_row + ui_height)) $((term_height - 1))); do
    tput cup $row 0
    tput el
  done
}

# Always scroll by UI height
scroll_lines=$ui_height  # Always scroll by full UI height
for i in $(seq 1 $scroll_lines); do
  printf "\n"
done
# Recheck term_height after scrolling
term_height=$(tput lines)

# Determine state and position UI
if [ $remaining_height -ge $ui_height ]; then
  # STATE_A: Enough space initially, use original cursor position
  draw_row=$((start_row - 1))
  if [ $draw_row -lt 0 ]; then
    draw_row=0
  fi
else
  # STATE_B: Position UI at bottom after scrolling
  draw_row=$((term_height - ui_height))
  if [ $draw_row -lt 0 ]; then
    draw_row=0
  fi
fi

# Hide cursor
tput civis

# Suppress ^C output
stty -echoctl 2>/dev/null || true

# Cleanup on exit
cleanup() {
  tput cnorm
  stty echoctl 2>/dev/null || true
  tput cup $((draw_row + ui_height)) 0
  exit 0
}
trap cleanup EXIT INT TERM
trap handle_resize SIGWINCH

# Initialize content arrays based on the specified line count
top_lines=()
bottom_lines=()
for i in $(seq 1 $lines_per_section); do
  top_lines+=("Log $i: $([ $i -le 8 ] && echo "$(echo "Start Init Run Check Test OK Good Ready" | cut -d' ' -f$i)" || echo "Line $i")")
  bottom_lines+=("Data $i: $([ $i -le 8 ] && echo "$(echo "A B C D E F G H" | cut -d' ' -f$i)" || echo "Item $i")")
done

# Draw UI
draw_rectangles

# Simulate scrolling updates
counter=$((lines_per_section + 1))
while true; do
  # Shift existing lines up
  for i in $(seq 0 $((lines_per_section - 2))); do
    top_lines[$i]=${top_lines[$((i + 1))]}
    bottom_lines[$i]=${bottom_lines[$((i + 1))]}
  done
  
  # Add new line at the bottom
  top_lines[$((lines_per_section - 1))]="Log $counter: Update $((counter - lines_per_section))"
  bottom_lines[$((lines_per_section - 1))]="Data $counter: $((counter - lines_per_section))"
  counter=$((counter + 1))
  
  update_content $((draw_row + 1)) "${top_lines[@]}"
  update_content $((draw_row + top_lines_count + 2)) "${bottom_lines[@]}"
  tput cup $((draw_row + ui_height)) 0
  sleep 1
done
