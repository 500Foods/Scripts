#!/usr/bin/env bash

# tables.sh - Library for JSON to ANSI tables
declare -r TABLES_VERSION="1.0.2"
DEBUG_FLAG=false
declare -g COLUMN_COUNT=0 MAX_LINES=1 THEME_NAME="Red" DEFAULT_PADDING=1

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source remaining library modules
# source "$SCRIPT_DIR/tables_datatypes.sh" # Integrated
# source "$SCRIPT_DIR/tables_config.sh" # Integrated
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

# CONFIG SECTION (from tables_config.sh)
# Global variables for title/footer
declare -gx TABLE_TITLE="" TITLE_WIDTH=0 TITLE_POSITION="none"
declare -gx TABLE_FOOTER="" FOOTER_WIDTH=0 FOOTER_POSITION="none"

# Global arrays for table config
declare -ax HEADERS=() KEYS=() JUSTIFICATIONS=() DATATYPES=() NULL_VALUES=() ZERO_VALUES=()
declare -ax FORMATS=() SUMMARIES=() BREAKS=() STRING_LIMITS=() WRAP_MODES=() WRAP_CHARS=()
declare -ax PADDINGS=() WIDTHS=() SORT_KEYS=() SORT_DIRECTIONS=() SORT_PRIORITIES=()
declare -ax IS_WIDTH_SPECIFIED=() VISIBLES=()

# validate_input_files: Check if files exist
validate_input_files() {
    local layout_file="$1" data_file="$2"; debug_log "Validating input files"
    [[ ! -s "$layout_file" || ! -s "$data_file" ]] && echo -e "${THEME[border_color]}Error: Layout or data JSON file empty/missing${THEME[text_color]}" >&2 && return 1
    return 0
}

# parse_layout_file: Extract theme/columns/sort from JSON
parse_layout_file() {
    local layout_file="$1"; debug_log "Parsing layout file"
    local columns_json sort_json
    THEME_NAME=$(jq -r '.theme // "Red"' "$layout_file")
    TABLE_TITLE=$(jq -r '.title // ""' "$layout_file")
    TITLE_POSITION=$(jq -r '.title_position // "none"' "$layout_file" | tr '[:upper:]' '[:lower:]')
    TABLE_FOOTER=$(jq -r '.footer // ""' "$layout_file")
    FOOTER_POSITION=$(jq -r '.footer_position // "none"' "$layout_file" | tr '[:upper:]' '[:lower:]')
    columns_json=$(jq -c '.columns // []' "$layout_file")
    sort_json=$(jq -c '.sort // []' "$layout_file")
    case "$TITLE_POSITION" in left|right|center|full|none) ;; *) echo -e "${THEME[border_color]}Warning: Invalid title position '$TITLE_POSITION', using 'none'${THEME[text_color]}" >&2; TITLE_POSITION="none";; esac
    case "$FOOTER_POSITION" in left|right|center|full|none) ;; *) echo -e "${THEME[border_color]}Warning: Invalid footer position '$FOOTER_POSITION', using 'none'${THEME[text_color]}" >&2; FOOTER_POSITION="none";; esac
    [[ -z "$columns_json" || "$columns_json" == "[]" ]] && echo -e "${THEME[border_color]}Error: No columns defined in layout JSON${THEME[text_color]}" >&2 && return 1
    parse_column_config "$columns_json"; parse_sort_config "$sort_json"
}

# parse_column_config: Process column configs
parse_column_config() {
    local columns_json="$1"; debug_log "Parsing column config"
    HEADERS=(); KEYS=(); JUSTIFICATIONS=(); DATATYPES=(); NULL_VALUES=(); ZERO_VALUES=()
    FORMATS=(); SUMMARIES=(); BREAKS=(); STRING_LIMITS=(); WRAP_MODES=(); WRAP_CHARS=()
    PADDINGS=(); WIDTHS=(); IS_WIDTH_SPECIFIED=(); VISIBLES=()
    local column_count=$(jq '. | length' <<<"$columns_json"); COLUMN_COUNT=$column_count
    for ((i=0; i<column_count; i++)); do
        local col_json=$(jq -c ".[$i]" <<<"$columns_json")
        HEADERS[i]=$(jq -r '.header // ""' <<<"$col_json")
        KEYS[i]=$(jq -r '.key // (.header | ascii_downcase | gsub("[^a-z0-9]"; "_"))' <<<"$col_json")
        JUSTIFICATIONS[i]=$(jq -r '.justification // "left"' <<<"$col_json" | tr '[:upper:]' '[:lower:]')
        DATATYPES[i]=$(jq -r '.datatype // "text"' <<<"$col_json" | tr '[:upper:]' '[:lower:]')
        NULL_VALUES[i]=$(jq -r '.null_value // "blank"' <<<"$col_json" | tr '[:upper:]' '[:lower:]')
        ZERO_VALUES[i]=$(jq -r '.zero_value // "blank"' <<<"$col_json" | tr '[:upper:]' '[:lower:]')
        FORMATS[i]=$(jq -r '.format // ""' <<<"$col_json")
        SUMMARIES[i]=$(jq -r '.summary // "none"' <<<"$col_json" | tr '[:upper:]' '[:lower:]')
        BREAKS[i]=$(jq -r '.break // false' <<<"$col_json")
        STRING_LIMITS[i]=$(jq -r '.string_limit // 0' <<<"$col_json")
        WRAP_MODES[i]=$(jq -r '.wrap_mode // "clip"' <<<"$col_json" | tr '[:upper:]' '[:lower:]')
        WRAP_CHARS[i]=$(jq -r '.wrap_char // ""' <<<"$col_json")
        PADDINGS[i]=$(jq -r '.padding // '"$DEFAULT_PADDING" <<<"$col_json")
        local visible_raw=$(jq -r '.visible // true' <<<"$col_json")
        local visible_key_check=$(jq -r 'has("visible")' <<<"$col_json")
        if [[ "$visible_key_check" == "true" ]]; then
            local visible_value=$(jq -r '.visible' <<<"$col_json")
            VISIBLES[i]="$visible_value"
        else
            VISIBLES[i]="$visible_raw"
        fi
        validate_column_config "$i" "${HEADERS[$i]}" "${JUSTIFICATIONS[$i]}" "${DATATYPES[$i]}" "${SUMMARIES[$i]}"
    done
    for ((i=0; i<COLUMN_COUNT; i++)); do
        local col_json=$(jq -c ".[$i]" <<<"$columns_json")
        local specified_width=$(jq -r '.width // 0' <<<"$col_json")
        if [[ $specified_width -gt 0 ]]; then
            WIDTHS[i]=$specified_width
            IS_WIDTH_SPECIFIED[i]="true"
            debug_log "Width specified for column $i (${HEADERS[$i]}): ${WIDTHS[$i]}"
        else
            WIDTHS[i]=$((${#HEADERS[i]} + (2 * PADDINGS[i])))
            IS_WIDTH_SPECIFIED[i]="false"
            debug_log "Width not specified for column $i (${HEADERS[$i]}), using header length: ${WIDTHS[$i]}"
        fi
        debug_log "Initial width for column $i (${HEADERS[$i]}): ${WIDTHS[$i]} (including padding ${PADDINGS[$i]}), Width specified: ${IS_WIDTH_SPECIFIED[$i]}"
    done
    debug_log "After parse_column_config - Number of columns: $COLUMN_COUNT"
    debug_log "After parse_column_config - Headers: ${HEADERS[*]}"
    debug_log "After parse_column_config - Keys: ${KEYS[*]}"
    debug_log "After parse_column_config - Visibles: ${VISIBLES[*]}"
}

# validate_column_config: Validate column config
validate_column_config() {
    local i="$1" header="$2" justification="$3" datatype="$4" summary="$5"
    [[ -z "$header" ]] && echo -e "${THEME[border_color]}Error: Column $i has no header${THEME[text_color]}" >&2 && return 1
    [[ "$justification" != "left" && "$justification" != "right" && "$justification" != "center" ]] && echo -e "${THEME[border_color]}Warning: Invalid justification '$justification' for column $header, using 'left'${THEME[text_color]}" >&2 && JUSTIFICATIONS[i]="left"
    [[ -z "${DATATYPE_HANDLERS[${datatype}_validate]}" ]] && echo -e "${THEME[border_color]}Warning: Invalid datatype '$datatype' for column $header, using 'text'${THEME[text_color]}" >&2 && DATATYPES[i]="text"
    local valid_summaries="${DATATYPE_HANDLERS[${DATATYPES[$i]}_summary_types]}"
    [[ "$summary" != "none" && ! " $valid_summaries " =~ $summary ]] && echo -e "${THEME[border_color]}Warning: Summary '$summary' not supported for datatype '${DATATYPES[$i]}' in column $header, using 'none'${THEME[text_color]}" >&2 && SUMMARIES[i]="none"
}

# parse_sort_config: Process sort configs
parse_sort_config() {
    local sort_json="$1"; debug_log "Parsing sort config"
    SORT_KEYS=(); SORT_DIRECTIONS=(); SORT_PRIORITIES=()
    local sort_count=$(jq '. | length' <<<"$sort_json")
    for ((i=0; i<sort_count; i++)); do
        local sort_item=$(jq -c ".[$i]" <<<"$sort_json")
        SORT_KEYS[i]=$(jq -r '.key // ""' <<<"$sort_item")
        SORT_DIRECTIONS[i]=$(jq -r '.direction // "asc"' <<<"$sort_item" | tr '[:upper:]' '[:lower:]')
        SORT_PRIORITIES[i]=$(jq -r '.priority // 0' <<<"$sort_item")
        [[ -z "${SORT_KEYS[$i]}" ]] && echo -e "${THEME[border_color]}Warning: Sort item $i has no key, ignoring${THEME[text_color]}" >&2 && continue
        [[ "${SORT_DIRECTIONS[$i]}" != "asc" && "${SORT_DIRECTIONS[$i]}" != "desc" ]] && echo -e "${THEME[border_color]}Warning: Invalid sort direction '${SORT_DIRECTIONS[$i]}' for key ${SORT_KEYS[$i]}, using 'asc'${THEME[text_color]}" >&2 && SORT_DIRECTIONS[i]="asc"
    done
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
