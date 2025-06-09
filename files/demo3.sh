#!/bin/bash

# Default values
LINES=8
APP_NAME="Fancy App v1.0"
SOURCE="Source: /var/log/app.log"
DEST="Dest: remote-server:5432"
SUMMARY="Summary: 150 processed, 3 errors"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --lines)
            LINES="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Colors
GREEN='\033[32m'
WHITE='\033[37m'
RESET='\033[0m'
GREEN_BG='\033[42m'

# Box drawing characters
TOP_LEFT='╭'
TOP_RIGHT='╮'
BOTTOM_LEFT='╰'
BOTTOM_RIGHT='╯'
HORIZONTAL='─'
VERTICAL='│'
LEFT_HALF='├'
RIGHT_HALF='┤'

# Get terminal width
TERM_WIDTH=$(tput cols)
CONTENT_WIDTH=$((TERM_WIDTH - 2))

start_time=$(date +%s)

draw_ui() {
    local elapsed=$(($(date +%s) - start_time))
    
    # Clear screen and move to top
    clear
    tput cup 0 0
    
    # Top border
    echo -e "${GREEN}${TOP_LEFT}$(printf "%*s" $((TERM_WIDTH-2)) | tr ' ' "${HORIZONTAL}")${TOP_RIGHT}${RESET}"
    
    # Header line
    printf "${GREEN}${VERTICAL}${RESET} %-*s ${GREEN}${VERTICAL}${RESET}\n" $((CONTENT_WIDTH-1)) "$APP_NAME"
    
    # Source section header
    printf "${GREEN}${LEFT_HALF}${GREEN_BG}${WHITE} %-*s ${RESET}${GREEN}${RIGHT_HALF}${RESET}\n" $((CONTENT_WIDTH-2)) "$SOURCE"
    
    # Source log lines
    for ((i=1; i<=LINES; i++)); do
        printf "${GREEN}${VERTICAL}${RESET} Log entry %d from source %-*s ${GREEN}${VERTICAL}${RESET}\n" $i $((CONTENT_WIDTH-25)) ""
    done
    
    # Destination section header
    printf "${GREEN}${LEFT_HALF}${GREEN_BG}${WHITE} %-*s ${RESET}${GREEN}${RIGHT_HALF}${RESET}\n" $((CONTENT_WIDTH-2)) "$DEST"
    
    # Destination log lines
    for ((i=1; i<=LINES; i++)); do
        printf "${GREEN}${VERTICAL}${RESET} Transfer %d to destination %-*s ${GREEN}${VERTICAL}${RESET}\n" $i $((CONTENT_WIDTH-26)) ""
    done
    
    # Summary section header
    printf "${GREEN}${LEFT_HALF}${GREEN_BG}${WHITE} %-*s ${RESET}${GREEN}${RIGHT_HALF}${RESET}\n" $((CONTENT_WIDTH-2)) "$SUMMARY"
    
    # Footer line with elapsed time
    printf "${GREEN}${VERTICAL}${RESET} Elapsed: %02d:%02d:%02d %-*s ${GREEN}${VERTICAL}${RESET}\n" $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60)) $((CONTENT_WIDTH-18)) ""
    
    # Bottom border
    echo -e "${GREEN}${BOTTOM_LEFT}$(printf "%*s" $((TERM_WIDTH-2)) | tr ' ' "${HORIZONTAL}")${BOTTOM_RIGHT}${RESET}"
}

# Main loop
trap 'tput cnorm; exit' INT TERM
tput civis  # Hide cursor

while true; do
    draw_ui
    sleep 1
done
