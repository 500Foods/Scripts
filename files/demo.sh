#!/bin/bash

# Ensure UTF-8 support for box-drawing characters (e.g., ╭, ╮)
export LC_ALL=en_US.UTF-8

# Define terminal-independent colors using tput
RED=$(tput setaf 1)    # Red for UI borders
YELLOW=$(tput setaf 3) # Yellow for content text
RESET=$(tput sgr0)     # Reset attributes

# Get initial terminal dimensions
term_width=$(tput cols)
term_height=$(tput lines)

# Query cursor position to find command’s row
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

# Define UI structure
top_lines_count=8
bottom_lines_count=8
ui_height=$((1 + top_lines_count + 1 + bottom_lines_count + 1 + 1))  # 20 lines

# Calculate lines available *below* cursor
remaining_height=$((term_height - start_row - 1))

# Set UI width
box_width=$term_width
inner_width=$((box_width - 2))

# Draw UI rectangles
draw_rectangles() {
  tput cup $draw_row 0
  printf "${RED}╭%*s╮${RESET}" $((box_width - 2)) "$(printf '─%.0s' $(seq 1 $((box_width - 2))))"
  for row in {1..8}; do
    tput cup $((draw_row + row)) 0
    printf "${RED}│%*s│${RESET}" $inner_width ""
  done
  tput cup $((draw_row + 9)) 0
  printf "${RED}├%*s┤${RESET}" $((box_width - 2)) "$(printf '─%.0s' $(seq 1 $((box_width - 2))))"
  for row in {10..17}; do
    tput cup $((draw_row + row)) 0
    printf "${RED}│%*s│${RESET}" $inner_width ""
  done
  tput cup $((draw_row + 18)) 0
  printf "${RED}╰%*s╯${RESET}" $((box_width - 2)) "$(printf '─%.0s' $(seq 1 $((box_width - 2))))"
}

# Update content in rectangles
update_content() {
  local base_row=$1
  local lines=("${@:2}")
  for i in {0..7}; do
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
  for row in $(seq $((draw_row + 19)) $((term_height - 1))); do
    tput cup $row 0
    tput el
  done
}

# Always scroll by UI height
scroll_lines=$(( ui_height - 1)) # Always scroll by full UI height
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
  tput cup $((draw_row + 19)) 0
  exit 0
}
trap cleanup EXIT INT TERM
trap handle_resize SIGWINCH

# Initialize content
top_lines=("Log 1: Start" "Log 2: Init" "Log 3: Run" "Log 4: Check" "Log 5: Test" "Log 6: OK" "Log 7: Good" "Log 8: Ready")
bottom_lines=("Data 1: A" "Data 2: B" "Data 3: C" "Data 4: D" "Data 5: E" "Data 6: F" "Data 7: G" "Data 8: H")

# Draw UI
draw_rectangles

# Simulate scrolling updates
counter=9
while true; do
  for i in {0..6}; do
    top_lines[$i]=${top_lines[$((i + 1))]}
    bottom_lines[$i]=${bottom_lines[$((i + 1))]}
  done
  top_lines[7]="Log $counter: Update $((counter - 8))"
  bottom_lines[7]="Data $counter: $((counter - 8))"
  counter=$((counter + 1))
  update_content $((draw_row + 1)) "${top_lines[@]}"
  update_content $((draw_row + 10)) "${bottom_lines[@]}"
  tput cup $((draw_row + 19)) 0
  sleep 1
done
