#!/usr/bin/env bash

# tables.sh - A library for rendering JSON data as ANSI tables

declare -r TABLES_VERSION="1.0.2"
DEBUG_FLAG=false

# Global variables
declare -g COLUMN_COUNT=0
declare -g MAX_LINES=1
declare -g THEME_NAME="Red"
declare -g DEFAULT_PADDING=1

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library modules (excluding integrated files)
source "$SCRIPT_DIR/tables_datatypes.sh"
source "$SCRIPT_DIR/tables_config.sh"
source "$SCRIPT_DIR/tables_data.sh"
source "$SCRIPT_DIR/tables_render.sh"

# THEMES SECTION (from tables_themes.sh)
declare -A RED_THEME=(
    [border_color]='\033[0;31m'  # Red border
    [caption_color]='\033[0;32m' # Green captions
    [header_color]='\033[1;37m'  # White header
    [footer_color]='\033[0;36m'  # Cyan footer
    [summary_color]='\033[1;37m' # White summary
    [text_color]='\033[0m'       # Default text
    [tl_corner]='╭'              # Top-left
    [tr_corner]='╮'              # Top-right
    [bl_corner]='╰'              # Bottom-left
    [br_corner]='╯'              # Bottom-right
    [h_line]='─'                 # Horizontal
    [v_line]='│'                 # Vertical
    [t_junct]='┬'                # Top junction
    [b_junct]='┴'                # Bottom junction
    [l_junct]='├'                # Left junction
    [r_junct]='┤'                # Right junction
    [cross]='┼'                  # Cross
)

declare -A BLUE_THEME=(
    [border_color]='\033[0;34m'  # Blue border
    [caption_color]='\033[0;34m' # Blue captions
    [header_color]='\033[1;37m'  # White header
    [footer_color]='\033[0;36m'  # Cyan footer
    [summary_color]='\033[1;37m' # White summary
    [text_color]='\033[0m'       # Default text
    [tl_corner]='╭'              # Top-left
    [tr_corner]='╮'              # Top-right
    [bl_corner]='╰'              # Bottom-left
    [br_corner]='╯'              # Bottom-right
    [h_line]='─'                 # Horizontal
    [v_line]='│'                 # Vertical
    [t_junct]='┬'                # Top junction
    [b_junct]='┴'                # Bottom junction
    [l_junct]='├'                # Left junction
    [r_junct]='┤'                # Right junction
    [cross]='┼'                  # Cross
)

# Initialize current theme to RED_THEME
declare -A THEME
for key in "${!RED_THEME[@]}"; do
    THEME[$key]="${RED_THEME[$key]}"
done

# get_theme: Updates active theme by name (e.g., "Red", "Blue")
get_theme() {
    local theme_name="$1"
    unset THEME
    declare -g -A THEME
    case "${theme_name,,}" in
        red)
            for key in "${!RED_THEME[@]}"; do
                THEME[$key]="${RED_THEME[$key]}"
            done
            ;;
        blue)
            for key in "${!BLUE_THEME[@]}"; do
                THEME[$key]="${BLUE_THEME[$key]}"
            done
            ;;
        *)
            for key in "${!RED_THEME[@]}"; do
                THEME[$key]="${RED_THEME[$key]}"
            done
            echo -e "${THEME[border_color]}Warning: Unknown theme '$theme_name', using Red${THEME[text_color]}" >&2
            ;;
    esac
}

# Debug logger function with millisecond timestamps
debug_log() {
    [[ "$DEBUG_FLAG" == "true" ]] && echo "[DEBUG] $(date +%s%3N)ms: $*" >&2
}

# show_help: Display usage and options
show_help() {
    cat << 'EOF'
tables.sh - Library for rendering JSON data as ANSI tables
USAGE: tables.sh <layout_json> <data_json> [OPTIONS] | [--help|--version]
OPTIONS: --debug (debug logs), --version (version info), --help (this message)
EOF
}

# calculate_title_width: Compute title width
calculate_title_width() {
    local title="$1" total_table_width="$2"
    if [[ -n "$title" ]]; then
        local evaluated_title=$(eval "echo \"$title\"")
        if [[ "$TITLE_POSITION" == "none" ]]; then
            TITLE_WIDTH=$((${#evaluated_title} + (2 * DEFAULT_PADDING)))
        elif [[ "$TITLE_POSITION" == "full" ]]; then
            TITLE_WIDTH=$total_table_width
        else
            TITLE_WIDTH=$((${#evaluated_title} + (2 * DEFAULT_PADDING)))
            [[ $TITLE_WIDTH -gt $total_table_width ]] && TITLE_WIDTH=$total_table_width
        fi
    else
        TITLE_WIDTH=0
    fi
}

# calculate_footer_width: Compute footer width
calculate_footer_width() {
    local footer="$1" total_table_width="$2"
    if [[ -n "$footer" ]]; then
        local evaluated_footer=$(eval "echo \"$footer\"")
        if [[ "$FOOTER_POSITION" == "none" ]]; then
            FOOTER_WIDTH=$((${#evaluated_footer} + (2 * DEFAULT_PADDING)))
        elif [[ "$FOOTER_POSITION" == "full" ]]; then
            FOOTER_WIDTH=$total_table_width
        else
            FOOTER_WIDTH=$((${#evaluated_footer} + (2 * DEFAULT_PADDING)))
            [[ $FOOTER_WIDTH -gt $total_table_width ]] && FOOTER_WIDTH=$total_table_width
        fi
    else
        FOOTER_WIDTH=0
    fi
}

# calculate_table_width: Compute total table width for visible columns
calculate_table_width() {
    local width=0 visible_count=0
    for ((i=0; i<COLUMN_COUNT; i++)); do
        if [[ "${VISIBLES[i]}" == "true" ]]; then
            ((width += WIDTHS[i]))
            ((visible_count++))
        fi
    done
    [[ $visible_count -gt 1 ]] && ((width += visible_count - 1))
    echo "$width"
}

# draw_table: Main function to render an ANSI table from JSON layout and data files
draw_table() {
    local layout_file="$1" data_file="$2" debug=false
    
    # Handle help and version options without requiring files
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        show_help
        return 0
    fi
    
    if [[ "$1" == "--version" ]]; then
        echo "tables.sh version $TABLES_VERSION"
        return 0
    fi
    
    # Check if no arguments provided
    if [[ $# -eq 0 ]]; then
        show_help
        return 0
    fi
    
    # Check if required files are provided
    if [[ -z "$layout_file" || -z "$data_file" ]]; then
        echo "Error: Both layout and data files are required" >&2
        echo "Use --help for usage information" >&2
        return 1
    fi
    
    shift 2
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --debug) debug=true; shift ;;
            --version) echo "tables.sh version $TABLES_VERSION"; return 0 ;;
            --help|-h) show_help; return 0 ;;
            *) echo "Error: Unknown option: $1" >&2; echo "Use --help for usage information" >&2; return 1 ;;
        esac
    done

    # Set debug flag
    DEBUG_FLAG="$debug"
    debug_log "Starting table rendering with debug=$debug"
    
    # Validate input files
    validate_input_files "$layout_file" "$data_file" || return 1
    
    # Parse layout JSON and set theme
    parse_layout_file "$layout_file" || return 1
    get_theme "$THEME_NAME"
    
    # Initialize summaries
    initialize_summaries
    
    # Read and prepare data
    prepare_data "$data_file"
    
    # Sort data if specified
    sort_data
    
    # Process data rows and update summaries
    process_data_rows
    
    debug_log "RENDERING TABLE"
    
    # Calculate total table width
    local total_table_width=$(calculate_table_width)
    
    # Render table components
    [[ -n "$TABLE_TITLE" ]] && render_table_title "$total_table_width"
    render_table_top_border
    render_table_headers
    render_table_separator "middle"
    render_data_rows "$MAX_LINES"
    
    # Render summaries if needed
    has_summaries=false
    render_summaries_row && has_summaries=true
    
    # Render bottom border and footer
    render_table_bottom_border
    [[ -n "$TABLE_FOOTER" ]] && render_table_footer "$total_table_width"
    
    debug_log "Table rendering complete"
}

# Main: Call draw_table with all arguments
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    draw_table "$@"
fi
