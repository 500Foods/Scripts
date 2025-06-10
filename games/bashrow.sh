#!/bin/bash

# BashRow - A Complete Tetris Game in Bash
# Version 1.0

set -e

# Game configuration
GAME_NAME="BashRow"
GAME_VERSION="1.0"
DEFAULT_DELAY=1000
DEMO_TIMEOUT=30
BOARD_WIDTH=10
BOARD_HEIGHT=20
PREVIEW_SIZE=4

# Dynamic sizing variables
ACTUAL_BOARD_WIDTH=10
ACTUAL_BOARD_HEIGHT=20
INFO_PANEL_WIDTH=25
LEFT_PANEL_X=1
LEFT_PANEL_Y=1
GAME_PANEL_X=0
GAME_PANEL_Y=1

# Colors using ANSI escape codes (foreground colors)
declare -A COLORS=(
    [0]="\033[0m"      # Reset
    [1]="\033[31m"     # Red (I-piece)
    [2]="\033[32m"     # Green (O-piece)
    [3]="\033[33m"     # Yellow (T-piece)
    [4]="\033[34m"     # Blue (S-piece)
    [5]="\033[35m"     # Magenta (Z-piece)
    [6]="\033[36m"     # Cyan (J-piece)
    [7]="\033[37m"     # White (L-piece)
    [8]="\033[30m"     # Black (empty)
)

# Tetromino shapes (4x4 grids, 0=empty, 1-7=colored blocks)
declare -A PIECES=(
    # I-piece (Red)
    [I]="0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,0"
    # O-piece (Green)
    [O]="0,0,0,0,0,2,2,0,0,2,2,0,0,0,0,0"
    # T-piece (Yellow)
    [T]="0,0,0,0,0,3,0,0,3,3,3,0,0,0,0,0"
    # S-piece (Blue)
    [S]="0,0,0,0,0,4,4,0,4,4,0,0,0,0,0,0"
    # Z-piece (Magenta)
    [Z]="0,0,0,0,5,5,0,0,0,5,5,0,0,0,0,0"
    # J-piece (Cyan)
    [J]="0,0,0,0,6,0,0,0,6,6,6,0,0,0,0,0"
    # L-piece (White)
    [L]="0,0,0,0,0,0,7,0,7,7,7,0,0,0,0,0"
)

# Game state variables
declare -a BOARD
declare -a CURRENT_PIECE
declare -a NEXT_PIECE
CURRENT_X=0
CURRENT_Y=0
CURRENT_ROTATION=0
PREV_X=0
PREV_Y=0
PREV_ROTATION=0
PREV_PIECE=""
SCORE=0
LINES_CLEARED=0
LEVEL=1
DROP_DELAY=$DEFAULT_DELAY
DEMO_MODE=true
DEMO_START_TIME=0
GAME_OVER=false
PAUSED=false
BOARD_NEEDS_FULL_REDRAW=true
PREV_SCORE=0
PREV_LINES_CLEARED=0
PREV_LEVEL=0
PREV_DEMO_MODE=true
PREV_NEXT_PIECE=""

# Terminal dimensions
TERM_WIDTH=0
TERM_HEIGHT=0

# Initialize the game board
init_board() {
    BOARD=()
    for ((i = 0; i < BOARD_WIDTH * BOARD_HEIGHT; i++)); do
        BOARD[i]=0
    done
}

# Get board cell value
get_board() {
    local x=$1 y=$2
    if [[ $x -lt 0 || $x -ge $BOARD_WIDTH || $y -lt 0 || $y -ge $BOARD_HEIGHT ]]; then
        echo 1  # Treat out-of-bounds as solid
    else
        echo ${BOARD[$((y * BOARD_WIDTH + x))]}
    fi
}

# Set board cell value
set_board() {
    local x=$1 y=$2 value=$3
    if [[ $x -ge 0 && $x -lt $BOARD_WIDTH && $y -ge 0 && $y -lt $BOARD_HEIGHT ]]; then
        BOARD[$((y * BOARD_WIDTH + x))]=$value
    fi
}

# Get piece cell value (4x4 grid)
get_piece() {
    local piece_name=$1 rotation=$2 x=$3 y=$4
    local piece_data=${PIECES[$piece_name]}
    IFS=',' read -ra piece_array <<< "$piece_data"
    
    # Apply rotation
    local rx ry
    case $rotation in
        0) rx=$x; ry=$y ;;
        1) rx=$((3-y)); ry=$x ;;
        2) rx=$((3-x)); ry=$((3-y)) ;;
        3) rx=$y; ry=$((3-x)) ;;
    esac
    
    if [[ $rx -ge 0 && $rx -lt 4 && $ry -ge 0 && $ry -lt 4 ]]; then
        echo ${piece_array[$((ry * 4 + rx))]}
    else
        echo 0
    fi
}

# Check if piece can be placed at position
can_place_piece() {
    local piece_name=$1 rotation=$2 px=$3 py=$4
    
    for ((y = 0; y < 4; y++)); do
        for ((x = 0; x < 4; x++)); do
            local piece_cell=$(get_piece "$piece_name" "$rotation" "$x" "$y")
            if [[ $piece_cell -ne 0 ]]; then
                local board_x=$((px + x))
                local board_y=$((py + y))
                local board_cell=$(get_board "$board_x" "$board_y")
                if [[ $board_cell -ne 0 ]]; then
                    return 1  # Cannot place
                fi
            fi
        done
    done
    return 0  # Can place
}

# Place piece on board
place_piece() {
    local piece_name=$1 rotation=$2 px=$3 py=$4
    
    for ((y = 0; y < 4; y++)); do
        for ((x = 0; x < 4; x++)); do
            local piece_cell=$(get_piece "$piece_name" "$rotation" "$x" "$y")
            if [[ $piece_cell -ne 0 ]]; then
                local board_x=$((px + x))
                local board_y=$((py + y))
                set_board "$board_x" "$board_y" "$piece_cell"
            fi
        done
    done
}

# Generate random piece
random_piece() {
    local pieces=(I O T S Z J L)
    echo ${pieces[$((RANDOM % 7))]}
}

# Reset game state for new game
reset_game() {
    SCORE=0
    LINES_CLEARED=0
    LEVEL=1
    DROP_DELAY=$DEFAULT_DELAY
    DEMO_MODE=false
    GAME_OVER=false
    PAUSED=false
    BOARD_NEEDS_FULL_REDRAW=true
    PREV_SCORE=0
    PREV_LINES_CLEARED=0
    PREV_LEVEL=0
    PREV_DEMO_MODE=false
    PREV_NEXT_PIECE=""
    CURRENT_PIECE=()
    NEXT_PIECE=()
    PREV_PIECE=""
    
    # Clear board
    init_board
    
    # Generate first pieces
    NEXT_PIECE[0]=$(random_piece)
    new_piece
}

# Initialize new piece
new_piece() {
    CURRENT_PIECE[0]=${NEXT_PIECE[0]}
    NEXT_PIECE[0]=$(random_piece)
    CURRENT_X=$((BOARD_WIDTH / 2 - 2))
    CURRENT_Y=0
    CURRENT_ROTATION=0
    
    # Check game over
    if ! can_place_piece "${CURRENT_PIECE[0]}" "$CURRENT_ROTATION" "$CURRENT_X" "$CURRENT_Y"; then
        GAME_OVER=true
    fi
}

# Clear completed lines
clear_lines() {
    local lines_to_clear=()
    
    # Find completed lines
    for ((y = 0; y < BOARD_HEIGHT; y++)); do
        local complete=true
        for ((x = 0; x < BOARD_WIDTH; x++)); do
            if [[ $(get_board "$x" "$y") -eq 0 ]]; then
                complete=false
                break
            fi
        done
        if $complete; then
            lines_to_clear+=($y)
        fi
    done
    
    # Clear lines and update score
    local cleared=${#lines_to_clear[@]}
    if [[ $cleared -gt 0 ]]; then
        # Remove cleared lines
        for line in "${lines_to_clear[@]}"; do
            for ((y = line; y > 0; y--)); do
                for ((x = 0; x < BOARD_WIDTH; x++)); do
                    set_board "$x" "$y" "$(get_board "$x" "$((y-1))")"
                done
            done
            # Clear top line
            for ((x = 0; x < BOARD_WIDTH; x++)); do
                set_board "$x" 0 0
            done
        done
        
        # Update score
        LINES_CLEARED=$((LINES_CLEARED + cleared))
        case $cleared in
            1) SCORE=$((SCORE + 40 * LEVEL)) ;;
            2) SCORE=$((SCORE + 100 * LEVEL)) ;;
            3) SCORE=$((SCORE + 300 * LEVEL)) ;;
            4) SCORE=$((SCORE + 1200 * LEVEL)) ;;
        esac
        
        # Update level
        LEVEL=$(((LINES_CLEARED / 10) + 1))
        DROP_DELAY=$((DEFAULT_DELAY - (LEVEL - 1) * 50))
        if [[ $DROP_DELAY -lt 100 ]]; then
            DROP_DELAY=100
        fi
        
        # Board changed, need full redraw
        BOARD_NEEDS_FULL_REDRAW=true
    fi
}

# Get terminal dimensions and calculate optimal board size
get_terminal_size() {
    TERM_WIDTH=$(tput cols)
    TERM_HEIGHT=$(tput lines)
    
    # Calculate optimal board dimensions to fill terminal
    # Reserve space for info panel (left side) and borders
    local available_width=$((TERM_WIDTH - INFO_PANEL_WIDTH - 4))  # 4 for borders and spacing
    local available_height=$((TERM_HEIGHT - 4))  # 4 for top/bottom borders and spacing
    
    # Each block is 2 characters wide, so divide by 2
    ACTUAL_BOARD_WIDTH=$((available_width / 2))
    # Reserve 2 lines for top and bottom borders of game panel
    ACTUAL_BOARD_HEIGHT=$((available_height - 2))
    
    # Maintain minimum playable size
    if [[ $ACTUAL_BOARD_WIDTH -lt 10 ]]; then
        ACTUAL_BOARD_WIDTH=10
    fi
    if [[ $ACTUAL_BOARD_HEIGHT -lt 20 ]]; then
        ACTUAL_BOARD_HEIGHT=20
    fi
    
    # Maintain reasonable maximum size for gameplay
    if [[ $ACTUAL_BOARD_WIDTH -gt 20 ]]; then
        ACTUAL_BOARD_WIDTH=20
    fi
    if [[ $ACTUAL_BOARD_HEIGHT -gt 40 ]]; then
        ACTUAL_BOARD_HEIGHT=40
    fi
    
    # Update board dimensions if they changed
    if [[ $ACTUAL_BOARD_WIDTH -ne $BOARD_WIDTH || $ACTUAL_BOARD_HEIGHT -ne $BOARD_HEIGHT ]]; then
        BOARD_WIDTH=$ACTUAL_BOARD_WIDTH
        BOARD_HEIGHT=$ACTUAL_BOARD_HEIGHT
        # Reinitialize board with new dimensions
        init_board
        # Reset current piece position to center
        if [[ -n ${CURRENT_PIECE[0]} ]]; then
            CURRENT_X=$((BOARD_WIDTH / 2 - 2))
        fi
    fi
}

# Draw a rounded rectangle
draw_rounded_rect() {
    local x=$1 y=$2 width=$3 height=$4
    
    # Top border
    tput cup $y $x
    printf "╭"
    for ((i = 1; i < width - 1; i++)); do
        printf "─"
    done
    printf "╮"
    
    # Side borders
    for ((i = 1; i < height - 1; i++)); do
        tput cup $((y + i)) $x
        printf "│"
        tput cup $((y + i)) $((x + width - 1))
        printf "│"
    done
    
    # Bottom border
    tput cup $((y + height - 1)) $x
    printf "╰"
    for ((i = 1; i < width - 1; i++)); do
        printf "─"
    done
    printf "╯"
}

# Clear area inside rectangle
clear_rect_interior() {
    local x=$1 y=$2 width=$3 height=$4
    
    for ((i = 1; i < height - 1; i++)); do
        tput cup $((y + i)) $((x + 1))
        for ((j = 1; j < width - 1; j++)); do
            printf " "
        done
    done
}

# Initialize display with static elements
init_display() {
    clear
    tput civis  # Hide cursor
    stty -echo  # Disable echo
    
    get_terminal_size
    
    # Calculate panel positions and sizes
    LEFT_PANEL_X=1
    LEFT_PANEL_Y=1
    local left_panel_width=$INFO_PANEL_WIDTH
    local left_panel_height=$((TERM_HEIGHT - 2))
    
    GAME_PANEL_X=$((INFO_PANEL_WIDTH + 2))
    GAME_PANEL_Y=1
    local game_panel_width=$((TERM_WIDTH - INFO_PANEL_WIDTH - 3))
    local game_panel_height=$((TERM_HEIGHT - 2))
    
    # Draw left panel rectangle
    draw_rounded_rect $LEFT_PANEL_X $LEFT_PANEL_Y $left_panel_width $left_panel_height
    
    # Draw game panel rectangle
    draw_rounded_rect $GAME_PANEL_X $GAME_PANEL_Y $game_panel_width $game_panel_height
    
    # Draw static info in left panel
    draw_static_info
}

# Restore terminal
cleanup_display() {
    tput cnorm  # Show cursor
    stty echo   # Enable echo
    clear
}

# Draw a colored block using outlined square
draw_block() {
    local color=$1
    if [[ $color -eq 0 ]]; then
        printf "  "  # Empty space
    else
        printf "${COLORS[$color]}▢${COLORS[0]} "
    fi
}

# Draw static info in left panel (called once during init)
draw_static_info() {
    local start_x=$((LEFT_PANEL_X + 2))
    local start_y=$((LEFT_PANEL_Y + 2))
    
    # Game title and version
    tput cup $start_y $start_x
    printf "\033[1m%s v%s\033[0m" "$GAME_NAME" "$GAME_VERSION"
}

# Update dynamic info in left panel (only when changed)
update_info_panel() {
    local start_x=$((LEFT_PANEL_X + 2))
    local start_y=$((LEFT_PANEL_Y + 2))
    local needs_update=false
    
    # Check if anything changed
    if [[ $SCORE -ne $PREV_SCORE || $LINES_CLEARED -ne $PREV_LINES_CLEARED || $LEVEL -ne $PREV_LEVEL || 
          "${NEXT_PIECE[0]}" != "$PREV_NEXT_PIECE" || $DEMO_MODE != $PREV_DEMO_MODE ]]; then
        needs_update=true
    fi
    
    if $needs_update; then
        # Clear previous dynamic content
        for ((i = 2; i <= 15; i++)); do
            tput cup $((start_y + i)) $start_x
            printf "                    "  # Clear line
        done
        
        # Score
        tput cup $((start_y + 2)) $start_x
        printf "Score: %d" "$SCORE"
        
        # Lines
        tput cup $((start_y + 3)) $start_x
        printf "Lines: %d" "$LINES_CLEARED"
        
        # Level
        tput cup $((start_y + 4)) $start_x
        printf "Level: %d" "$LEVEL"
        
        # Board dimensions
        tput cup $((start_y + 5)) $start_x
        printf "Board: %dx%d" "$BOARD_WIDTH" "$BOARD_HEIGHT"
        
        # Next piece
        tput cup $((start_y + 7)) $start_x
        printf "Next:"
        if [[ -n ${NEXT_PIECE[0]} ]]; then
            for ((y = 0; y < 4; y++)); do
                tput cup $((start_y + 8 + y)) $start_x
                for ((x = 0; x < 4; x++)); do
                    local cell=$(get_piece "${NEXT_PIECE[0]}" 0 "$x" "$y")
                    draw_block "$cell"
                done
            done
        fi
        
        # Demo mode indicator
        if $DEMO_MODE; then
            local elapsed=$(($(date +%s) - DEMO_START_TIME))
            local remaining=$((DEMO_TIMEOUT - elapsed))
            if [[ $remaining -lt 0 ]]; then
                remaining=0
            fi
            tput cup $((start_y + 13)) $start_x
            printf "\033[33mDEMO MODE\033[0m"
            tput cup $((start_y + 14)) $start_x
            printf "Countdown: %ds" "$remaining"
            tput cup $((start_y + 15)) $start_x
            printf "Press any key to play"
        fi
        
        # Update previous values
        PREV_SCORE=$SCORE
        PREV_LINES_CLEARED=$LINES_CLEARED
        PREV_LEVEL=$LEVEL
        PREV_NEXT_PIECE=${NEXT_PIECE[0]}
        PREV_DEMO_MODE=$DEMO_MODE
    fi
}

# Draw a single cell on the board
draw_board_cell() {
    local x=$1 y=$2
    local board_start_x=$((GAME_PANEL_X + 3))
    local board_start_y=$((GAME_PANEL_Y + 2))
    
    if [[ $x -ge 0 && $x -lt $BOARD_WIDTH && $y -ge 0 && $y -lt $BOARD_HEIGHT ]]; then
        tput cup $((board_start_y + y)) $((board_start_x + x * 2))
        local cell=$(get_board "$x" "$y")
        draw_block "$cell"
    fi
}

# Draw the game board in the right panel (optimized)
update_game_board() {
    local board_start_x=$((GAME_PANEL_X + 3))
    local board_start_y=$((GAME_PANEL_Y + 2))
    
    if $BOARD_NEEDS_FULL_REDRAW; then
        # Full redraw when needed (after line clears, etc.)
        for ((y = 0; y < BOARD_HEIGHT; y++)); do
            tput cup $((board_start_y + y)) $board_start_x
            for ((x = 0; x < BOARD_WIDTH; x++)); do
                local cell=$(get_board "$x" "$y")
                draw_block "$cell"
            done
        done
        BOARD_NEEDS_FULL_REDRAW=false
    else
        # Clear previous piece position
        if [[ -n $PREV_PIECE ]]; then
            for ((py = 0; py < 4; py++)); do
                for ((px = 0; px < 4; px++)); do
                    local piece_cell=$(get_piece "$PREV_PIECE" "$PREV_ROTATION" "$px" "$py")
                    if [[ $piece_cell -ne 0 ]]; then
                        local board_x=$((PREV_X + px))
                        local board_y=$((PREV_Y + py))
                        draw_board_cell "$board_x" "$board_y"
                    fi
                done
            done
        fi
    fi
    
    # Draw current piece
    if [[ -n ${CURRENT_PIECE[0]} ]]; then
        for ((py = 0; py < 4; py++)); do
            for ((px = 0; px < 4; px++)); do
                local piece_cell=$(get_piece "${CURRENT_PIECE[0]}" "$CURRENT_ROTATION" "$px" "$py")
                if [[ $piece_cell -ne 0 ]]; then
                    local board_x=$((CURRENT_X + px))
                    local board_y=$((CURRENT_Y + py))
                    if [[ $board_x -ge 0 && $board_x -lt $BOARD_WIDTH && $board_y -ge 0 && $board_y -lt $BOARD_HEIGHT ]]; then
                        tput cup $((board_start_y + board_y)) $((board_start_x + board_x * 2))
                        draw_block "$piece_cell"
                    fi
                fi
            done
        done
    fi
    
    # Update previous position tracking
    PREV_X=$CURRENT_X
    PREV_Y=$CURRENT_Y
    PREV_ROTATION=$CURRENT_ROTATION
    PREV_PIECE=${CURRENT_PIECE[0]}
}

# Main drawing function - only updates what's needed
draw_screen() {
    update_info_panel
    update_game_board
}

# Move piece
move_piece() {
    local dx=$1 dy=$2
    local new_x=$((CURRENT_X + dx))
    local new_y=$((CURRENT_Y + dy))
    
    if can_place_piece "${CURRENT_PIECE[0]}" "$CURRENT_ROTATION" "$new_x" "$new_y"; then
        CURRENT_X=$new_x
        CURRENT_Y=$new_y
        return 0
    fi
    return 1
}

# Rotate piece
rotate_piece() {
    local new_rotation=$(((CURRENT_ROTATION + 1) % 4))
    
    if can_place_piece "${CURRENT_PIECE[0]}" "$new_rotation" "$CURRENT_X" "$CURRENT_Y"; then
        CURRENT_ROTATION=$new_rotation
        return 0
    fi
    return 1
}

# Hard drop piece
hard_drop() {
    while move_piece 0 1; do
        SCORE=$((SCORE + 2))
    done
}

# Demo AI - simple strategy
demo_ai() {
    local action=$((RANDOM % 10))
    
    case $action in
        0|1) move_piece -1 0 ;;  # Move left
        2|3) move_piece 1 0 ;;   # Move right
        4) rotate_piece ;;       # Rotate
        5) hard_drop ;;          # Hard drop occasionally
        *) ;;                    # Do nothing
    esac
}

# Handle input
handle_input() {
    local key
    if read -t 0.1 -n 1 key 2>/dev/null; then
        if $DEMO_MODE; then
            DEMO_MODE=false
        fi
        
        case $key in
            $'\e') # Escape sequence (arrow keys)
                read -t 0.1 -n 1 key
                if [[ $key == '[' ]]; then
                    read -t 0.1 -n 1 key
                    case $key in
                        'A') rotate_piece ;;        # Up arrow - rotate
                        'B') hard_drop ;;           # Down arrow - hard drop
                        'C') move_piece 1 0 ;;      # Right arrow - move right
                        'D') move_piece -1 0 ;;     # Left arrow - move left
                    esac
                fi
                ;;
            ' ') move_piece 0 1 ;;  # Space for soft drop
            'q'|'Q') exit 0 ;;
            'p'|'P') PAUSED=$(!PAUSED) ;;
        esac
    fi
}

# Game loop
game_loop() {
    local last_drop=0
    DEMO_START_TIME=$(date +%s)
    
    while ! $GAME_OVER; do
        local current_time=$(date +%s%3N)  # Milliseconds
        
        # Handle demo mode timeout
        if $DEMO_MODE; then
            local elapsed=$(($(date +%s) - DEMO_START_TIME))
            if [[ $elapsed -ge $DEMO_TIMEOUT ]]; then
                break
            fi
        fi
        
        # Handle input
        handle_input
        
        if ! $PAUSED; then
            # Demo AI
            if $DEMO_MODE && [[ $((RANDOM % 5)) -eq 0 ]]; then
                demo_ai
            fi
            
            # Drop piece
            if [[ $((current_time - last_drop)) -ge $DROP_DELAY ]]; then
                if ! move_piece 0 1; then
                    # Piece landed
                    place_piece "${CURRENT_PIECE[0]}" "$CURRENT_ROTATION" "$CURRENT_X" "$CURRENT_Y"
                    clear_lines
                    
                    # Get next piece
                    CURRENT_PIECE[0]=${NEXT_PIECE[0]}
                    NEXT_PIECE[0]=$(random_piece)
                    CURRENT_X=$((BOARD_WIDTH / 2 - 2))
                    CURRENT_Y=0
                    CURRENT_ROTATION=0
                    
                    # Check game over
                    if ! can_place_piece "${CURRENT_PIECE[0]}" "$CURRENT_ROTATION" "$CURRENT_X" "$CURRENT_Y"; then
                        GAME_OVER=true
                    fi
                fi
                last_drop=$current_time
            fi
        fi
        
        # Draw screen
        draw_screen
        
        # Small delay to prevent excessive CPU usage
        sleep 0.02
    done
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --delay)
                DROP_DELAY="$2"
                DEFAULT_DELAY="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [--delay MILLISECONDS]"
                echo "  --delay: Set drop delay in milliseconds (default: 1000)"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    parse_args "$@"
    
    # Set up signal handlers
    trap cleanup_display EXIT
    trap 'exit 0' INT TERM
    
    # Initialize display once
    init_display
    
    # Main game loop - restart after each game
    while true; do
        # Start in demo mode
        DEMO_MODE=true
        DEMO_START_TIME=$(date +%s)
        
        # Initialize game
        init_board
        NEXT_PIECE[0]=$(random_piece)
        new_piece
        
        # Start game loop
        game_loop
        
        # Game over screen
        tput cup $((TERM_HEIGHT / 2)) $((TERM_WIDTH / 2 - 15))
        if $DEMO_MODE; then
            printf "\033[33mDemo completed!\033[0m"
        else
            printf "\033[31mGame Over!\033[0m"
        fi
        tput cup $((TERM_HEIGHT / 2 + 1)) $((TERM_WIDTH / 2 - 15))
        printf "Final Score: %d" "$SCORE"
        tput cup $((TERM_HEIGHT / 2 + 2)) $((TERM_WIDTH / 2 - 15))
        printf "Press any key to start new game..."
        
        # Wait for key press to restart
        read -n 1
        
        # Reset for new game
        reset_game
        
        # Redraw the display
        init_display
    done
}

# Run the game
main "$@"
