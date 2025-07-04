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
# source "$SCRIPT_DIR/tables_data.sh" # Integrated
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

# DATA SECTION (from tables_data.sh)
# Global arrays for data storage and summaries
declare -a ROW_JSONS=()
declare -A SUM_SUMMARIES=() COUNT_SUMMARIES=() MIN_SUMMARIES=() MAX_SUMMARIES=()
declare -A UNIQUE_VALUES=() AVG_SUMMARIES=() AVG_COUNTS=()
declare -a IS_WIDTH_SPECIFIED=()
declare -a DATA_ROWS=()

# initialize_summaries: Initialize summaries storage
initialize_summaries() {
    debug_log "Initializing summaries storage"
    SUM_SUMMARIES=(); COUNT_SUMMARIES=(); MIN_SUMMARIES=(); MAX_SUMMARIES=()
    UNIQUE_VALUES=(); AVG_SUMMARIES=(); AVG_COUNTS=()
    for ((i=0; i<COLUMN_COUNT; i++)); do
        SUM_SUMMARIES[$i]=0; COUNT_SUMMARIES[$i]=0; MIN_SUMMARIES[$i]=""; MAX_SUMMARIES[$i]=""
        UNIQUE_VALUES[$i]=""; AVG_SUMMARIES[$i]=0; AVG_COUNTS[$i]=0
    done
}

# prepare_data: Read and validate data from JSON file
prepare_data() {
    local data_file="$1"; debug_log "Preparing data from file: $data_file"
    DATA_ROWS=()
    local data_json=$(jq -c '. // []' "$data_file")
    local row_count=$(jq '. | length' <<<"$data_json"); debug_log "Data row count: $row_count"
    [[ $row_count -eq 0 ]] && debug_log "No data rows to load." && return
    local jq_expr=".[] | ["
    for key in "${KEYS[@]}"; do jq_expr+=".${key} // null,"; done
    jq_expr="${jq_expr%,}] | join(\"\t\")"
    local all_data=$(jq -r "$jq_expr" "$data_file")
    IFS=$'\n' read -d '' -r -a rows <<< "$all_data"
    for ((i=0; i<row_count; i++)); do
        IFS=$'\t' read -r -a values <<< "${rows[$i]}"
        declare -A row_data
        for ((j=0; j<${#KEYS[@]}; j++)); do
            local key="${KEYS[$j]}" value="${values[$j]}"
            [[ "$value" == "null" ]] && value="null" || value="${value:-null}"
            row_data["$key"]="$value"
        done
        DATA_ROWS[$i]=$(declare -p row_data); debug_log "Loaded row $i into memory"
    done
    debug_log "After loading, DATA_ROWS length: ${#DATA_ROWS[@]}"
}

# sort_data: Apply sorting to data
sort_data() {
    debug_log "Sorting data"; debug_log "DATA_ROWS length before processing sort: ${#DATA_ROWS[@]}"
    [[ ${#SORT_KEYS[@]} -eq 0 ]] && debug_log "No sort keys defined, skipping sort" && return
    debug_log "Performing in-memory sorting"
    local indices=(); for ((i=0; i<${#DATA_ROWS[@]}; i++)); do indices+=("$i"); done
    get_sort_value() {
        local idx="$1" key="$2"
        declare -A row_data
        if ! eval "${DATA_ROWS[$idx]}"; then
            debug_log "Error evaluating DATA_ROWS[$idx]"
            echo ""
            return
        fi
        if [[ -v "row_data[$key]" ]]; then
            echo "${row_data[$key]}"
        else
            debug_log "Key $key not found in row_data for sort"
            echo ""
        fi
    }
    local primary_key="${SORT_KEYS[0]}" primary_dir="${SORT_DIRECTIONS[0]}"
    debug_log "Sorting by primary key: $primary_key, direction: $primary_dir"
    local sorted_indices=()
    IFS=$'\n' read -d '' -r -a sorted_indices < <(for idx in "${indices[@]}"; do
        value=$(get_sort_value "$idx" "$primary_key"); printf "%s\t%s\n" "$value" "$idx"
    done | sort -k1,1${primary_dir:0:1} | cut -f2)
    local temp_rows=("${DATA_ROWS[@]}"); DATA_ROWS=()
    for idx in "${sorted_indices[@]}"; do
        DATA_ROWS+=("${temp_rows[$idx]}"); debug_log "Moved row $idx to new position in sorted order"
    done
    debug_log "Data sorted successfully in-memory"
}

# process_data_rows: Process data rows, update widths and calculate summaries
process_data_rows() {
    debug_log "DATA_ROWS length before processing: ${#DATA_ROWS[@]}"
    local row_count; MAX_LINES=1; row_count=${#DATA_ROWS[@]}; debug_log "Processing $row_count rows of data from DATA_ROWS (length: ${#DATA_ROWS[@]})"
    [[ $row_count -eq 0 ]] && debug_log "WARNING: No data rows loaded. Check data file or input."
    debug_log "Number of columns: $COLUMN_COUNT"; debug_log "Column headers: ${HEADERS[*]}"
    debug_log "Column keys: ${KEYS[*]}"; debug_log "Initial widths: ${WIDTHS[*]}"
    ROW_JSONS=()
    for ((i=0; i<row_count; i++)); do
        local row_json line_count=1; row_json="{\"row\":$i}"; ROW_JSONS+=("$row_json")
        debug_log "Processing row $i from memory"
        declare -A row_data
        if ! eval "${DATA_ROWS[$i]}"; then
            debug_log "Error evaluating DATA_ROWS[$i], skipping row"
            continue
        fi
        for ((j=0; j<COLUMN_COUNT; j++)); do
            local key="${KEYS[$j]}" datatype="${DATATYPES[$j]}" format="${FORMATS[$j]}" string_limit="${STRING_LIMITS[$j]}" wrap_mode="${WRAP_MODES[$j]}" wrap_char="${WRAP_CHARS[$j]}"
            local validate_fn="${DATATYPE_HANDLERS[${datatype}_validate]}" format_fn="${DATATYPE_HANDLERS[${datatype}_format]}"
            local value="null"
            if [[ -v "row_data[$key]" ]]; then
                value="${row_data[$key]}"
                debug_log "Key $key found in row_data with value: $value"
            else
                debug_log "Key $key not found in row_data, defaulting to null"
            fi
            value=$("$validate_fn" "$value")
            local display_value=$("$format_fn" "$value" "$format" "$string_limit" "$wrap_mode" "$wrap_char")
            debug_log "Column $j (${HEADERS[$j]}): Raw value='$value', Formatted value='$display_value'"
            if [[ "$value" == "null" ]]; then
                case "${NULL_VALUES[$j]}" in 0) display_value="0";; missing) display_value="Missing";; *) display_value="";; esac
                debug_log "Null value handling: '$value' -> '$display_value'"
            elif [[ "$value" == "0" || "$value" == "0m" || "$value" == "0M" || "$value" == "0G" || "$value" == "0K" ]]; then
                case "${ZERO_VALUES[$j]}" in 0) display_value="0";; missing) display_value="Missing";; *) display_value="";; esac
                debug_log "Zero value handling: '$value' -> '$display_value'"
            fi
            if [[ "${IS_WIDTH_SPECIFIED[j]}" != "true" && "${VISIBLES[j]}" == "true" ]]; then
                if [[ -n "$wrap_char" && "$wrap_mode" == "wrap" && -n "$display_value" && "$value" != "null" ]]; then
                    local max_len=0 IFS="$wrap_char"; read -ra parts <<<"$display_value"
                    for part in "${parts[@]}"; do
                        local len=$(echo -n "$part" | sed 's/\x1B\[[0-9;]*m//g' | wc -c)
                        [[ $len -gt $max_len ]] && max_len=$len
                    done
                    local padded_width=$((max_len + (2 * PADDINGS[j]))); [[ $padded_width -gt ${WIDTHS[j]} ]] && WIDTHS[j]=$padded_width
                    [[ ${#parts[@]} -gt $line_count ]] && line_count=${#parts[@]}; debug_log "Wrapped value: parts=${#parts[@]}, max_len=$max_len, new width=${WIDTHS[j]}"
                else
                    local len=$(echo -n "$display_value" | sed 's/\x1B\[[0-9;]*m//g' | wc -c)
                    local padded_width=$((len + (2 * PADDINGS[j]))); [[ $padded_width -gt ${WIDTHS[j]} ]] && WIDTHS[j]=$padded_width
                    debug_log "Plain value: len=$len, new width=${WIDTHS[$j]}"
                fi
            else debug_log "Enforcing specified width or visibility for column $j (${HEADERS[$j]}): width=${WIDTHS[j]} (from layout or hidden)"; fi
            update_summaries "$j" "$value" "${DATATYPES[$j]}" "${SUMMARIES[$j]}"
        done
        [[ $line_count -gt $MAX_LINES ]] && MAX_LINES=$line_count
    done
    for ((j=0; j<COLUMN_COUNT; j++)); do
        if [[ "${SUMMARIES[$j]}" != "none" ]]; then
            local summary_value="" datatype="${DATATYPES[$j]}" format="${FORMATS[$j]}"
            case "${SUMMARIES[$j]}" in
                sum)
                    if [[ -n "${SUM_SUMMARIES[$j]}" && "${SUM_SUMMARIES[$j]}" != "0" ]]; then
                        if [[ "$datatype" == "kcpu" ]]; then
                            local formatted_num=$(echo "${SUM_SUMMARIES[$j]}" | awk '{ printf "%\047d", $0 }')
                            summary_value="${formatted_num}m"
                        elif [[ "$datatype" == "kmem" ]]; then
                            local formatted_num=$(echo "${SUM_SUMMARIES[$j]}" | awk '{ printf "%\047d", $0 }')
                            summary_value="${formatted_num}M"
                        elif [[ "$datatype" == "num" ]]; then summary_value=$(format_num "${SUM_SUMMARIES[$j]}" "$format")
                        elif [[ "$datatype" == "int" || "$datatype" == "float" ]]; then summary_value="${SUM_SUMMARIES[$j]}"; [[ -n "$format" ]] && summary_value=$(printf '%s' "$summary_value"); fi
                    fi;;
                min) summary_value="${MIN_SUMMARIES[$j]:-}"; [[ -n "$format" ]] && summary_value=$(printf '%s' "$summary_value");;
                max) summary_value="${MAX_SUMMARIES[$j]:-}"; [[ -n "$format" ]] && summary_value=$(printf '%s' "$summary_value");;
                count) summary_value="${COUNT_SUMMARIES[$j]:-0}";;
                unique)
                    if [[ -n "${UNIQUE_VALUES[$j]}" ]]; then
                        local unique_count=$(echo "${UNIQUE_VALUES[$j]}" | tr ' ' '\n' | sort -u | wc -l | awk '{print $1}'); summary_value="$unique_count"
                    else summary_value="0"; fi;;
                avg)
                    if [[ -n "${AVG_SUMMARIES[$j]}" && "${AVG_COUNTS[$j]}" -gt 0 ]]; then
                        local avg_result=$(awk "BEGIN {printf \"%.10f\", ${AVG_SUMMARIES[$j]} / ${AVG_COUNTS[$j]}}")
                        if [[ "$datatype" == "int" ]]; then summary_value=$(printf "%.0f" "$avg_result")
                        elif [[ "$datatype" == "float" ]]; then
                            if [[ -n "$format" && "$format" =~ %.([0-9]+)f ]]; then local decimals="${BASH_REMATCH[1]}"; summary_value=$(printf "%.${decimals}f" "$avg_result")
                            else summary_value=$(printf "%.2f" "$avg_result"); fi
                        elif [[ "$datatype" == "num" ]]; then summary_value=$(format_num "$avg_result" "$format")
                        else summary_value="$avg_result"; fi
                    else summary_value="0"; fi;;
            esac
            if [[ -n "$summary_value" && "${IS_WIDTH_SPECIFIED[j]}" != "true" && "${VISIBLES[j]}" == "true" ]]; then
                local summary_len=$(echo -n "$summary_value" | sed 's/\x1B\[[0-9;]*m//g' | wc -c)
                local summary_padded_width=$((summary_len + (2 * PADDINGS[j])))
                if [[ $summary_padded_width -gt ${WIDTHS[j]} ]]; then
                    debug_log "Column $j (${HEADERS[$j]}): Adjusting width for summary value '$summary_value', new width=$summary_padded_width"
                    WIDTHS[j]=$summary_padded_width
                fi
            fi
        fi
    done
    debug_log "Final column widths after summary adjustment: ${WIDTHS[*]}"
    debug_log "Max lines per row: $MAX_LINES"
    debug_log "Total rows to render: ${#ROW_JSONS[@]} (DATA_ROWS length: ${#DATA_ROWS[@]})"
}

# update_summaries: Update summaries for a column
update_summaries() {
    local j="$1" value="$2" datatype="$3" summary_type="$4"
    case "$summary_type" in
        sum)
            if [[ "$datatype" == "kcpu" && "$value" =~ ^[0-9]+m$ ]]; then SUM_SUMMARIES[$j]=$(( ${SUM_SUMMARIES[$j]:-0} + ${value%m} ))
            elif [[ "$datatype" == "kmem" ]]; then
                if [[ "$value" =~ ^[0-9]+M$ ]]; then SUM_SUMMARIES[$j]=$(( ${SUM_SUMMARIES[$j]:-0} + ${value%M} ))
                elif [[ "$value" =~ ^[0-9]+G$ ]]; then SUM_SUMMARIES[$j]=$(( ${SUM_SUMMARIES[$j]:-0} + ${value%G} * 1000 ))
                elif [[ "$value" =~ ^[0-9]+K$ ]]; then SUM_SUMMARIES[$j]=$(( ${SUM_SUMMARIES[$j]:-0} + ${value%K} / 1000 ))
                elif [[ "$value" =~ ^[0-9]+Mi$ ]]; then SUM_SUMMARIES[$j]=$(( ${SUM_SUMMARIES[$j]:-0} + ${value%Mi} ))
                elif [[ "$value" =~ ^[0-9]+Gi$ ]]; then SUM_SUMMARIES[$j]=$(( ${SUM_SUMMARIES[$j]:-0} + ${value%Gi} * 1000 )); fi
            elif [[ "$datatype" == "int" || "$datatype" == "float" || "$datatype" == "num" ]]; then
                if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then SUM_SUMMARIES[$j]=$(awk "BEGIN {print (${SUM_SUMMARIES[$j]:-0} + $value)}"); fi
            fi;;
        min)
            if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                if [[ -z "${MIN_SUMMARIES[$j]}" ]] || awk "BEGIN {if ($value < ${MIN_SUMMARIES[$j]}) exit 0; else exit 1}" 2>/dev/null; then MIN_SUMMARIES[$j]="$value"; fi
            fi;;
        max)
            if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                if [[ -z "${MAX_SUMMARIES[$j]}" ]] || awk "BEGIN {if ($value > ${MAX_SUMMARIES[$j]}) exit 0; else exit 1}" 2>/dev/null; then MAX_SUMMARIES[$j]="$value"; fi
            fi;;
        count) if [[ -n "$value" && "$value" != "null" ]]; then COUNT_SUMMARIES[$j]=$(( ${COUNT_SUMMARIES[$j]:-0} + 1 )); fi;;
        unique) if [[ -n "$value" && "$value" != "null" ]]; then
            if [[ -z "${UNIQUE_VALUES[$j]}" ]]; then UNIQUE_VALUES[$j]="$value"; else UNIQUE_VALUES[$j]+=" $value"; fi; fi;;
        avg)
            if [[ "$datatype" == "int" || "$datatype" == "float" || "$datatype" == "num" ]]; then
                if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    AVG_SUMMARIES[$j]=$(awk "BEGIN {print (${AVG_SUMMARIES[$j]:-0} + $value)}"); AVG_COUNTS[$j]=$(( ${AVG_COUNTS[$j]:-0} + 1 )); fi
            fi;;
    esac
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
