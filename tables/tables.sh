#!/usr/bin/env bash

# tables.sh - Library for JSON to ANSI tables
declare -r TABLES_VERSION="1.0.2"
DEBUG_FLAG=false
declare -g COLUMN_COUNT=0 MAX_LINES=1 THEME_NAME="Red" DEFAULT_PADDING=1

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source remaining library modules
# source "$SCRIPT_DIR/tables_datatypes.sh" # Integrated
source "$SCRIPT_DIR/tables_config.sh"
source "$SCRIPT_DIR/tables_data.sh"
source "$SCRIPT_DIR/tables_render.sh"

# THEMES SECTION
declare -A RED_THEME=(
    [border_color]='\033[0;31m'  # Red
    [caption_color]='\033[0;32m' # Green
    [header_color]='\033[1;37m'  # White
    [footer_color]='\033[0;36m'  # Cyan
    [summary_color]='\033[1;37m' # White
    [text_color]='\033[0m'       # Default
    [tl_corner]='╭' [tr_corner]='╮' [bl_corner]='╰' [br_corner]='╯'
    [h_line]='─' [v_line]='│' [t_junct]='┬' [b_junct]='┴'
    [l_junct]='├' [r_junct]='┤' [cross]='┼'
)

declare -A BLUE_THEME=(
    [border_color]='\033[0;34m'  # Blue
    [caption_color]='\033[0;34m' # Blue
    [header_color]='\033[1;37m'  # White
    [footer_color]='\033[0;36m'  # Cyan
    [summary_color]='\033[1;37m' # White
    [text_color]='\033[0m'       # Default
    [tl_corner]='╭' [tr_corner]='╮' [bl_corner]='╰' [br_corner]='╯'
    [h_line]='─' [v_line]='│' [t_junct]='┬' [b_junct]='┴'
    [l_junct]='├' [r_junct]='┤' [cross]='┼'
)

# Initialize theme to RED_THEME
declare -A THEME
for key in "${!RED_THEME[@]}"; do THEME[$key]="${RED_THEME[$key]}"; done

# get_theme: Updates theme by name
get_theme() {
    local theme_name="$1"; unset THEME; declare -g -A THEME
    case "${theme_name,,}" in
        red) for key in "${!RED_THEME[@]}"; do THEME[$key]="${RED_THEME[$key]}"; done ;;
        blue) for key in "${!BLUE_THEME[@]}"; do THEME[$key]="${BLUE_THEME[$key]}"; done ;;
        *) for key in "${!RED_THEME[@]}"; do THEME[$key]="${RED_THEME[$key]}"; done
           echo -e "${THEME[border_color]}Warning: Unknown theme '$theme_name', using Red${THEME[text_color]}" >&2 ;;
    esac
}

# DATATYPES SECTION
declare -A DATATYPE_HANDLERS=(
    [text_validate]="validate_text" [text_format]="format_text" [text_summary_types]="count unique"
    [int_validate]="validate_number" [int_format]="format_number" [int_summary_types]="sum min max avg count unique"
    [num_validate]="validate_number" [num_format]="format_num" [num_summary_types]="sum min max avg count unique"
    [float_validate]="validate_number" [float_format]="format_number" [float_summary_types]="sum min max avg count unique"
    [kcpu_validate]="validate_kcpu" [kcpu_format]="format_kcpu" [kcpu_summary_types]="sum min max avg count unique"
    [kmem_validate]="validate_kmem" [kmem_format]="format_kmem" [kmem_summary_types]="sum min max avg count unique"
)

# Validation functions
validate_text() { local value="$1"; [[ "$value" != "null" ]] && echo "$value" || echo ""; }

validate_number() {
    local value="$1"
    if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ || "$value" == "0" || "$value" == "null" ]]; then echo "$value"; else echo ""; fi
}

validate_kcpu() {
    local value="$1"
    if [[ "$value" =~ ^[0-9]+m$ || "$value" == "0" || "$value" == "0m" || "$value" == "null" || "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then echo "$value"; else echo ""; fi
}

validate_kmem() {
    local value="$1"
    if [[ "$value" =~ ^[0-9]+[KMG]$ || "$value" =~ ^[0-9]+Mi$ || "$value" =~ ^[0-9]+Gi$ || "$value" =~ ^[0-9]+Ki$ || "$value" == "0" || "$value" == "null" ]]; then echo "$value"; else echo ""; fi
}

# Formatting functions
format_text() {
    local value="$1" format="$2" string_limit="$3" wrap_mode="$4" wrap_char="$5" justification="$6"
    [[ -z "$value" || "$value" == "null" ]] && { echo ""; return; }
    if [[ "$string_limit" -gt 0 && ${#value} -gt $string_limit ]]; then
        if [[ "$wrap_mode" == "wrap" && -n "$wrap_char" ]]; then
            local wrapped="" IFS="$wrap_char"; read -ra parts <<< "$value"
            for part in "${parts[@]}"; do wrapped+="$part\n"; done
            echo -e "$wrapped" | head -n $((string_limit / ${#wrap_char}))
        elif [[ "$wrap_mode" == "wrap" ]]; then echo "${value:0:$string_limit}"
        else
            case "$justification" in
                "right") echo "${value: -${string_limit}}";;
                "center") local start=$(( (${#value} - string_limit) / 2 )); echo "${value:${start}:${string_limit}}";;
                *) echo "${value:0:$string_limit}";;
            esac
        fi
    else echo "$value"; fi
}

format_number() {
    local value="$1" format="$2"
    [[ -z "$value" || "$value" == "null" || "$value" == "0" ]] && { echo ""; return; }
    [[ -n "$format" && "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]] && printf '%s' "$value" || echo "$value"
}

format_num() {
    local value="$1" format="$2"
    [[ -z "$value" || "$value" == "null" || "$value" == "0" ]] && { echo ""; return; }
    if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        [[ -n "$format" ]] && printf '%s' "$value" || printf "%s" "$(echo "$value" | awk '{ printf "%\047d", $0 }')"
    else echo "$value"; fi
}

format_kcpu() {
    local value="$1" format="$2"
    [[ -z "$value" || "$value" == "null" || "$value" == "0" || "$value" == "0m" ]] && { echo ""; return; }
    if [[ "$value" =~ ^[0-9]+m$ ]]; then
        local num_part="${value%m}" formatted_num=$(echo "$num_part" | awk '{ printf "%\047d", $0 }')
        echo "${formatted_num}m"
    elif [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        local num_value=$(awk "BEGIN {print $value * 1000}")
        printf "%sm" "$(echo "$num_value" | awk '{ printf "%\047d", $0 }')"
    else echo ""; fi
}

format_kmem() {
    local value="$1" format="$2"
    [[ -z "$value" || "$value" == "null" || "$value" =~ ^0[MKG]$ || "$value" == "0Mi" || "$value" == "0Gi" || "$value" == "0Ki" ]] && { echo ""; return; }
    if [[ "$value" =~ ^[0-9]+[KMG]$ ]]; then
        local num_part="${value%[KMG]}" unit="${value: -1}" formatted_num=$(echo "$num_part" | awk '{ printf "%\047d", $0 }')
        echo "${formatted_num}${unit}"
    elif [[ "$value" =~ ^[0-9]+Mi$ ]]; then
        local num_part="${value%Mi}" formatted_num=$(echo "$num_part" | awk '{ printf "%\047d", $0 }')
        echo "${formatted_num}M"
    elif [[ "$value" =~ ^[0-9]+Gi$ ]]; then
        local num_part="${value%Gi}" formatted_num=$(echo "$num_part" | awk '{ printf "%\047d", $0 }')
        echo "${formatted_num}G"
    elif [[ "$value" =~ ^[0-9]+Ki$ ]]; then
        local num_part="${value%Ki}" formatted_num=$(echo "$num_part" | awk '{ printf "%\047d", $0 }')
        echo "${formatted_num}K"
    else echo ""; fi
}

# format_display_value: Format cell value
format_display_value() {
    local value="$1" null_value="$2" zero_value="$3" datatype="$4" format="$5" string_limit="$6" wrap_mode="$7" wrap_char="$8" justification="$9"
    local validate_fn="${DATATYPE_HANDLERS[${datatype}_validate]}" format_fn="${DATATYPE_HANDLERS[${datatype}_format]}"
    value=$("$validate_fn" "$value"); local display_value=$("$format_fn" "$value" "$format" "$string_limit" "$wrap_mode" "$wrap_char" "$justification")
    if [[ "$value" == "null" ]]; then
        case "$null_value" in 0) display_value="0";; missing) display_value="Missing";; *) display_value="";; esac
    elif [[ "$value" == "0" || "$value" == "0m" || "$value" == "0M" || "$value" == "0G" || "$value" == "0K" ]]; then
        case "$zero_value" in 0) display_value="0";; missing) display_value="Missing";; *) display_value="";; esac
    fi
    echo "$display_value"
}

# Debug logger with ms timestamps
debug_log() { [[ "$DEBUG_FLAG" == "true" ]] && echo "[DEBUG] $(date +%s%3N)ms: $*" >&2; }

# show_help: Display usage
show_help() { cat << 'EOF'
tables.sh - JSON to ANSI tables
USAGE: tables.sh <layout_json> <data_json> [OPTIONS] | [--help|--version]
OPTIONS: --debug, --version, --help
EOF
}

# calculate_title_width: Compute title width
calculate_title_width() {
    local title="$1" total_table_width="$2"
    if [[ -n "$title" ]]; then
        local evaluated_title=$(eval "echo \"$title\"")
        if [[ "$TITLE_POSITION" == "none" ]]; then TITLE_WIDTH=$((${#evaluated_title} + (2 * DEFAULT_PADDING)))
        elif [[ "$TITLE_POSITION" == "full" ]]; then TITLE_WIDTH=$total_table_width
        else TITLE_WIDTH=$((${#evaluated_title} + (2 * DEFAULT_PADDING))); [[ $TITLE_WIDTH -gt $total_table_width ]] && TITLE_WIDTH=$total_table_width; fi
    else TITLE_WIDTH=0; fi
}

# calculate_footer_width: Compute footer width
calculate_footer_width() {
    local footer="$1" total_table_width="$2"
    if [[ -n "$footer" ]]; then
        local evaluated_footer=$(eval "echo \"$footer\"")
        if [[ "$FOOTER_POSITION" == "none" ]]; then FOOTER_WIDTH=$((${#evaluated_footer} + (2 * DEFAULT_PADDING)))
        elif [[ "$FOOTER_POSITION" == "full" ]]; then FOOTER_WIDTH=$total_table_width
        else FOOTER_WIDTH=$((${#evaluated_footer} + (2 * DEFAULT_PADDING))); [[ $FOOTER_WIDTH -gt $total_table_width ]] && FOOTER_WIDTH=$total_table_width; fi
    else FOOTER_WIDTH=0; fi
}

# calculate_table_width: Total width for visible columns
calculate_table_width() {
    local width=0 visible_count=0
    for ((i=0; i<COLUMN_COUNT; i++)); do [[ "${VISIBLES[i]}" == "true" ]] && ((width += WIDTHS[i])) && ((visible_count++)); done
    [[ $visible_count -gt 1 ]] && ((width += visible_count - 1)); echo "$width"
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
