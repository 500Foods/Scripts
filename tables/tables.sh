#!/usr/bin/env bash

# tables.sh: Reusable table-drawing library for rendering JSON data as ASCII tables
# Version: 1.0.0
# Functions: draw_table
# Usage: draw_table <layout_json_file> <data_json_file> [--debug] [--version]
# Dependencies: jq, bash 4.0+, awk, sed

# Version information
declare -r VERSION="1.0.0"

# Debug flag - can be set by parent script
DEBUG_FLAG=false

# Global variables
declare -g COLUMN_COUNT=0
declare -g MAX_LINES=1
declare -g THEME_NAME="Red"
declare -g DEFAULT_PADDING=1

# Themes for table styling
# Each theme defines colors and ASCII characters for table borders
declare -A RED_THEME=(
    [border_color]='\033[0;31m' # Red border color
    [header_color]='\033[0;32m' # Green header color
    [text_color]='\033[0m'      # Default text color (terminal default)
    [tl_corner]='╭'             # Top-left corner
    [tr_corner]='╮'             # Top-right corner
    [bl_corner]='╰'             # Bottom-left corner
    [br_corner]='╯'             # Bottom-right corner
    [h_line]='─'                # Horizontal line
    [v_line]='│'                # Vertical line
    [t_junct]='┬'              # Top junction
    [b_junct]='┴'              # Bottom junction
    [l_junct]='├'              # Left junction
    [r_junct]='┤'              # Right junction
    [cross]='┼'                 # Cross junction
)

declare -A BLUE_THEME=(
    [border_color]='\033[0;34m' # Blue border color
    [header_color]='\033[0;34m' # Blue header color
    [text_color]='\033[0m'      # Default text color
    [tl_corner]='╭'
    [tr_corner]='╮'
    [bl_corner]='╰'
    [br_corner]='╯'
    [h_line]='─'
    [v_line]='│'
    [t_junct]='┬'
    [b_junct]='┴'
    [l_junct]='├'
    [r_junct]='┤'
    [cross]='┼'
)

# Current theme, always initialized to RED_THEME
declare -A THEME
# Explicitly copy RED_THEME to THEME
for key in "${!RED_THEME[@]}"; do
    THEME[$key]="${RED_THEME[$key]}"
done

# Debug logger function
debug_log() {
    [[ "$DEBUG_FLAG" == "true" ]] && echo "[DEBUG] $*" >&2
}

# get_theme: Updates the active theme based on name
# Args: theme_name (string, e.g., "Red", "Blue")
# Side effect: Updates global THEME array
get_theme() {
    local theme_name="$1"
    # Clear existing THEME entries
    unset THEME
    declare -g -A THEME

    # Set new theme
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

# Datatype registry: Maps datatypes to validation, formatting, and total functions
# Format: [datatype_function]="function_name"
declare -A DATATYPE_HANDLERS=(
    [text_validate]="validate_text"
    [text_format]="format_text"
    [text_total_types]="count unique"
    [int_validate]="validate_number"
    [int_format]="format_number"
    [int_total_types]="sum min max count unique"
    [float_validate]="validate_number"
    [float_format]="format_number"
    [float_total_types]="sum min max count unique"
    [kcpu_validate]="validate_kcpu"
    [kcpu_format]="format_kcpu"
    [kcpu_total_types]="sum count"
    [kmem_validate]="validate_kmem"
    [kmem_format]="format_kmem"
    [kmem_total_types]="sum count"
)

# Validation functions: Ensure data matches expected format
# Each returns the validated value or empty string if invalid
validate_text() {
    local value="$1"
    [[ "$value" != "null" ]] && echo "$value" || echo ""
}

validate_number() {
    local value="$1"
    if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [[ "$value" == "0" ]] || [[ "$value" == "null" ]]; then
        echo "$value"
    else
        echo ""
    fi
}

validate_kcpu() {
    local value="$1"
    if [[ "$value" =~ ^[0-9]+m$ ]] || [[ "$value" == "0" ]] || [[ "$value" == "0m" ]] || [[ "$value" == "null" ]] || [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "$value"
    else
        echo ""
    fi
}

validate_kmem() {
    local value="$1"
    if [[ "$value" =~ ^[0-9]+[KMG]$ ]] || [[ "$value" =~ ^[0-9]+Mi$ ]] || [[ "$value" =~ ^[0-9]+Gi$ ]] || [[ "$value" =~ ^[0-9]+Ki$ ]] || [[ "$value" == "0" ]] || [[ "$value" == "null" ]]; then
        echo "$value"
    else
        echo ""
    fi
}

# Formatting functions: Convert validated data into display format
format_text() {
    local value="$1" format="$2" string_limit="$3" wrap_mode="$4" wrap_char="$5"
    [[ -z "$value" || "$value" == "null" ]] && { echo ""; return; }
    if [[ "$string_limit" -gt 0 && ${#value} -gt $string_limit ]]; then
        if [[ "$wrap_mode" == "clip" ]]; then
            echo "${value:0:$string_limit}"
        elif [[ -n "$wrap_char" ]]; then
            local wrapped=""
            local IFS="$wrap_char"
            read -ra parts <<< "$value"
            for part in "${parts[@]}"; do
                wrapped+="$part\n"
            done
            echo -e "$wrapped" | head -n $((string_limit / ${#wrap_char}))
        else
            echo "${value:0:$string_limit}"
        fi
    else
        echo "$value"
    fi
}

format_number() {
    local value="$1" format="$2"
    [[ -z "$value" || "$value" == "null" || "$value" == "0" ]] && { echo ""; return; }
    if [[ -n "$format" && "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        printf "$format" "$value"
    else
        echo "$value"
    fi
}

format_kcpu() {
    local value="$1" format="$2"
    [[ -z "$value" || "$value" == "null" || "$value" == "0" || "$value" == "0m" ]] && { echo ""; return; }
    if [[ "$value" =~ ^[0-9]+m$ ]]; then
        echo "$value"
    elif [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        printf "%.0fm" "$(awk "BEGIN {print $value * 1000}")"
    else
        echo ""
    fi
}

format_kmem() {
    local value="$1" format="$2"
    [[ -z "$value" || "$value" == "null" || "$value" =~ ^0[MKG]$ ]] && { echo ""; return; }
    if [[ "$value" =~ ^[0-9]+[KMG]$ ]]; then
        echo "$value"
    elif [[ "$value" =~ ^[0-9]+Mi$ ]]; then
        echo "${value%Mi}M"
    elif [[ "$value" =~ ^[0-9]+Gi$ ]]; then
        echo "${value%Gi}G"
    elif [[ "$value" =~ ^[0-9]+Ki$ ]]; then
        echo "${value%Ki}K"
    else
        echo ""
    fi
}

# Global arrays to store table configuration and data
declare -a HEADERS=()
declare -a KEYS=()
declare -a JUSTIFICATIONS=()
declare -a DATATYPES=()
declare -a NULL_VALUES=()
declare -a ZERO_VALUES=()
declare -a FORMATS=()
declare -a TOTALS=()
declare -a BREAKS=()
declare -a STRING_LIMITS=()
declare -a WRAP_MODES=()
declare -a WRAP_CHARS=()
declare -a PADDINGS=()
declare -a WIDTHS=()
declare -a SORT_KEYS=()
declare -a SORT_DIRECTIONS=()
declare -a SORT_PRIORITIES=()
declare -a ROW_JSONS=()
declare -A SUM_TOTALS=()
declare -A COUNT_TOTALS=()
declare -A MIN_TOTALS=()
declare -A MAX_TOTALS=()
declare -A UNIQUE_VALUES=()

# validate_input_files: Check if layout and data files exist and are valid
# Args: layout_file, data_file
# Returns: 0 if valid, 1 if invalid
validate_input_files() {
    local layout_file="$1" data_file="$2"
    debug_log "Validating input files: $layout_file, $data_file"
    
    if [[ ! -s "$layout_file" || ! -s "$data_file" ]]; then
        echo -e "${THEME[border_color]}Error: Layout or data JSON file is empty or missing${THEME[text_color]}" >&2
        return 1
    fi
    return 0
}

# parse_layout_file: Extract theme, columns, and sort information from layout JSON
# Args: layout_file
# Side effect: Updates global THEME_NAME, COLUMN_COUNT, HEADERS, KEYS, etc.
parse_layout_file() {
    local layout_file="$1"
    debug_log "Parsing layout file: $layout_file"
    
    local columns_json sort_json
    THEME_NAME=$(jq -r '.theme // "Red"' "$layout_file")
    columns_json=$(jq -c '.columns // []' "$layout_file")
    sort_json=$(jq -c '.sort // []' "$layout_file")
    
    debug_log "Theme: $THEME_NAME"
    debug_log "Columns JSON: $columns_json"
    debug_log "Sort JSON: $sort_json"
    
    if [[ -z "$columns_json" || "$columns_json" == "[]" ]]; then
        echo -e "${THEME[border_color]}Error: No columns defined in layout JSON${THEME[text_color]}" >&2
        return 1
    fi
    
    parse_column_config "$columns_json"
    parse_sort_config "$sort_json"
}

# parse_column_config: Process column configurations
# Args: columns_json
# Sets global arrays for column configuration
parse_column_config() {
    local columns_json="$1"
    debug_log "Parsing column configuration"
    
    # Clear all arrays first to ensure we start fresh
    HEADERS=()
    KEYS=()
    JUSTIFICATIONS=()
    DATATYPES=()
    NULL_VALUES=()
    ZERO_VALUES=()
    FORMATS=()
    TOTALS=()
    BREAKS=()
    STRING_LIMITS=()
    WRAP_MODES=()
    WRAP_CHARS=()
    WIDTHS=()
    
    local column_count=$(jq '. | length' <<<"$columns_json")
    debug_log "Column count: $column_count"
    
    # Store column count globally
    COLUMN_COUNT=$column_count
    
    for ((i=0; i<column_count; i++)); do
        local col_json
        col_json=$(jq -c ".[$i]" <<<"$columns_json")
        HEADERS[$i]=$(jq -r '.header // ""' <<<"$col_json")
        KEYS[$i]=$(jq -r '.key // (.header | ascii_downcase | gsub("[^a-z0-9]"; "_"))' <<<"$col_json")
        JUSTIFICATIONS[$i]=$(jq -r '.justification // "left"' <<<"$col_json" | tr '[:upper:]' '[:lower:]')
        DATATYPES[$i]=$(jq -r '.datatype // "text"' <<<"$col_json" | tr '[:upper:]' '[:lower:]')
        NULL_VALUES[$i]=$(jq -r '.null_value // "blank"' <<<"$col_json" | tr '[:upper:]' '[:lower:]')
        ZERO_VALUES[$i]=$(jq -r '.zero_value // "blank"' <<<"$col_json" | tr '[:upper:]' '[:lower:]')
        FORMATS[$i]=$(jq -r '.format // ""' <<<"$col_json")
        TOTALS[$i]=$(jq -r '.total // "none"' <<<"$col_json" | tr '[:upper:]' '[:lower:]')
        BREAKS[$i]=$(jq -r '.break // false' <<<"$col_json")
        STRING_LIMITS[$i]=$(jq -r '.string_limit // 0' <<<"$col_json")
        WRAP_MODES[$i]=$(jq -r '.wrap_mode // "clip"' <<<"$col_json" | tr '[:upper:]' '[:lower:]')
        WRAP_CHARS[$i]=$(jq -r '.wrap_char // ""' <<<"$col_json")
        PADDINGS[$i]=$(jq -r '.padding // '$DEFAULT_PADDING <<<"$col_json")
        
        debug_log "Column $i: Header=${HEADERS[$i]}, Key=${KEYS[$i]}, Datatype=${DATATYPES[$i]}"
        
        validate_column_config "$i" "${HEADERS[$i]}" "${JUSTIFICATIONS[$i]}" "${DATATYPES[$i]}" "${TOTALS[$i]}"
    done
    
    # Initialize column widths based on header lengths plus padding
    for ((i=0; i<COLUMN_COUNT; i++)); do
        WIDTHS[$i]=$((${#HEADERS[$i]} + (2 * ${PADDINGS[$i]})))
        debug_log "Initial width for column $i (${HEADERS[$i]}): ${WIDTHS[$i]} (including padding ${PADDINGS[$i]})"
    done
    
    # Debug verification of array contents
    debug_log "After parse_column_config - Number of columns: $COLUMN_COUNT"
    debug_log "After parse_column_config - Headers: ${HEADERS[*]}"
    debug_log "After parse_column_config - Keys: ${KEYS[*]}"
}

# validate_column_config: Validate column configuration and print warnings
# Args: column_index, header, justification, datatype, total
validate_column_config() {
    local i="$1" header="$2" justification="$3" datatype="$4" total="$5"
    
    if [[ -z "$header" ]]; then
        echo -e "${THEME[border_color]}Error: Column $i has no header${THEME[text_color]}" >&2
        return 1
    fi
    
    if [[ "$justification" != "left" && "$justification" != "right" && "$justification" != "center" ]]; then
        echo -e "${THEME[border_color]}Warning: Invalid justification '$justification' for column $header, using 'left'${THEME[text_color]}" >&2
        JUSTIFICATIONS[$i]="left"
    fi
    
    if [[ -z "${DATATYPE_HANDLERS[${datatype}_validate]}" ]]; then
        echo -e "${THEME[border_color]}Warning: Invalid datatype '$datatype' for column $header, using 'text'${THEME[text_color]}" >&2
        DATATYPES[$i]="text"
    fi
    
    local valid_totals="${DATATYPE_HANDLERS[${DATATYPES[$i]}_total_types]}"
    if [[ "$total" != "none" && ! " $valid_totals " =~ " $total " ]]; then
        echo -e "${THEME[border_color]}Warning: Total '$total' not supported for datatype '${DATATYPES[$i]}' in column $header, using 'none'${THEME[text_color]}" >&2
        TOTALS[$i]="none"
    fi
}

# parse_sort_config: Process sort configurations
# Args: sort_json
# Sets global arrays for sort configuration
parse_sort_config() {
    local sort_json="$1"
    debug_log "Parsing sort configuration"
    
    # Clear sort arrays
    SORT_KEYS=()
    SORT_DIRECTIONS=()
    SORT_PRIORITIES=()
    
    local sort_count=$(jq '. | length' <<<"$sort_json")
    debug_log "Sort count: $sort_count"
    
    for ((i=0; i<sort_count; i++)); do
        local sort_item
        sort_item=$(jq -c ".[$i]" <<<"$sort_json")
        SORT_KEYS[$i]=$(jq -r '.key // ""' <<<"$sort_item")
        SORT_DIRECTIONS[$i]=$(jq -r '.direction // "asc"' <<<"$sort_item" | tr '[:upper:]' '[:lower:]')
        SORT_PRIORITIES[$i]=$(jq -r '.priority // 0' <<<"$sort_item")
        
        debug_log "Sort $i: Key=${SORT_KEYS[$i]}, Direction=${SORT_DIRECTIONS[$i]}"
        
        if [[ -z "${SORT_KEYS[$i]}" ]]; then
            echo -e "${THEME[border_color]}Warning: Sort item $i has no key, ignoring${THEME[text_color]}" >&2
            continue
        fi
        
        if [[ "${SORT_DIRECTIONS[$i]}" != "asc" && "${SORT_DIRECTIONS[$i]}" != "desc" ]]; then
            echo -e "${THEME[border_color]}Warning: Invalid sort direction '${SORT_DIRECTIONS[$i]}' for key ${SORT_KEYS[$i]}, using 'asc'${THEME[text_color]}" >&2
            SORT_DIRECTIONS[$i]="asc"
        fi
    done
}

# initialize_totals: Initialize totals storage
initialize_totals() {
    debug_log "Initializing totals storage"
    
    # Clear total associative arrays
    SUM_TOTALS=()
    COUNT_TOTALS=()
    MIN_TOTALS=()
    MAX_TOTALS=()
    UNIQUE_VALUES=()
    
    for ((i=0; i<COLUMN_COUNT; i++)); do
        SUM_TOTALS[$i]=0
        COUNT_TOTALS[$i]=0
        MIN_TOTALS[$i]=""
        MAX_TOTALS[$i]=""
        UNIQUE_VALUES[$i]=""
    done
}

# prepare_data: Read and validate data from JSON file
# Args: data_file
# Returns: valid data JSON
prepare_data() {
    local data_file="$1"
    debug_log "Preparing data from file: $data_file"
    
    local data_json
    data_json=$(jq -c '. // []' "$data_file")
    
    local temp_data_file=$(mktemp)
    echo "[" > "$temp_data_file"
    
    local row_count=$(jq '. | length' <<<"$data_json")
    local valid_rows=0
    debug_log "Data row count: $row_count"
    
    for ((i=0; i<row_count; i++)); do
        local row_json
        row_json=$(jq -c ".[$i]" <<<"$data_json")
        debug_log "Row $i: $row_json"
        
        if [[ $i -gt 0 && $valid_rows -gt 0 ]]; then
            echo "," >> "$temp_data_file"
        fi
        echo "$row_json" >> "$temp_data_file"
        ((valid_rows++))
    done
    
    echo "]" >> "$temp_data_file"
    debug_log "Valid rows count: $valid_rows"
    
    cat "$temp_data_file"
    rm -f "$temp_data_file"
}

# sort_data: Apply sorting to data
# Args: data_json
# Returns: sorted data JSON
sort_data() {
    local data_json="$1"
    debug_log "Sorting data"
    
    if [[ ${#SORT_KEYS[@]} -eq 0 ]]; then
        debug_log "No sort keys defined, skipping sort"
        echo "$data_json"
        return
    fi
    
    local jq_sort=""
    for i in "${!SORT_KEYS[@]}"; do
        local key="${SORT_KEYS[$i]}" dir="${SORT_DIRECTIONS[$i]}"
        
        if [[ "$dir" == "desc" ]]; then
            jq_sort+=".${key} | reverse,"
        else
            jq_sort+=".${key},"
        fi
    done
    
    jq_sort=${jq_sort%,}
    debug_log "JQ sort expression: $jq_sort"
    
    if [[ -n "$jq_sort" ]]; then
        local temp_data_file=$(mktemp)
        echo "$data_json" > "$temp_data_file"
        
        local sorted_data=$(jq -c "sort_by($jq_sort)" "$temp_data_file" 2>/tmp/jq_stderr.$$)
        local jq_exit=$?
        
        rm -f "$temp_data_file"
        
        if [[ $jq_exit -ne 0 ]]; then
            echo -e "${THEME[border_color]}Error: Sorting failed${THEME[text_color]}" >&2
            cat /tmp/jq_stderr.$$ >&2
            rm -f /tmp/jq_stderr.$$
            echo "$data_json"  # Return original data on error
        else
            debug_log "Data sorted successfully"
            echo "$sorted_data"
        fi
    else
        echo "$data_json"
    fi
}

# process_data_rows: Process data rows, update widths and calculate totals
# Args: data_json
# Side effect: Updates global MAX_LINES
process_data_rows() {
    local data_json="$1"
    
    local row_count
    MAX_LINES=1
    row_count=$(jq '. | length' <<<"$data_json")
    
    debug_log "================ DATA PROCESSING ================"
    debug_log "Processing $row_count rows of data"
    debug_log "Number of columns: $COLUMN_COUNT"
    debug_log "Column headers: ${HEADERS[*]}"
    debug_log "Column keys: ${KEYS[*]}"
    debug_log "Initial widths: ${WIDTHS[*]}"
    
    # Clear previous row data
    ROW_JSONS=()
    
    for ((i=0; i<row_count; i++)); do
        local row_json line_count=1
        row_json=$(jq -c ".[$i]" <<<"$data_json")
        ROW_JSONS+=("$row_json")
        debug_log "Processing row $i: $row_json"
        
        for ((j=0; j<COLUMN_COUNT; j++)); do
            local key="${KEYS[$j]}" 
            local datatype="${DATATYPES[$j]}" 
            local format="${FORMATS[$j]}" 
            local string_limit="${STRING_LIMITS[$j]}" 
            local wrap_mode="${WRAP_MODES[$j]}" 
            local wrap_char="${WRAP_CHARS[$j]}"
            local validate_fn="${DATATYPE_HANDLERS[${datatype}_validate]}" 
            local format_fn="${DATATYPE_HANDLERS[${datatype}_format]}"
            local value
            
            value=$(jq -r ".${key} // null" <<<"$row_json")
            value=$("$validate_fn" "$value")
            local display_value=$("$format_fn" "$value" "$format" "$string_limit" "$wrap_mode" "$wrap_char")
            debug_log "Column $j (${HEADERS[$j]}): Raw value='$value', Formatted value='$display_value'"
            
            if [[ "$value" == "null" ]]; then
                case "${NULL_VALUES[$j]}" in
                    0) display_value="0" ;;
                    missing) display_value="Missing" ;;
                    *) display_value="" ;;
                esac
                debug_log "Null value handling: '$value' -> '$display_value'"
            elif [[ "$value" == "0" || "$value" == "0m" || "$value" == "0M" || "$value" == "0G" || "$value" == "0K" ]]; then
                case "${ZERO_VALUES[$j]}" in
                    0) display_value="0" ;;
                    missing) display_value="Missing" ;;
                    *) display_value="" ;;
                esac
                debug_log "Zero value handling: '$value' -> '$display_value'"
            fi
            
            # Update column width
            if [[ -n "$wrap_char" && "$wrap_mode" == "wrap" && -n "$display_value" && "$value" != "null" ]]; then
                local max_len=0
                local IFS="$wrap_char"
                read -ra parts <<<"$display_value"
                for part in "${parts[@]}"; do
                local len=$(echo -n "$part" | sed 's/\x1B\[[0-9;]*m//g' | wc -c)
                # Don't decrease length - we need the actual character count
                [[ $len -gt $max_len ]] && max_len=$len
                done
                local padded_width=$((max_len + (2 * ${PADDINGS[$j]})))
                [[ $padded_width -gt ${WIDTHS[$j]} ]] && WIDTHS[$j]=$padded_width
            [[ ${#parts[@]} -gt $line_count ]] && line_count=${#parts[@]}
            debug_log "Wrapped value: parts=${#parts[@]}, max_len=$max_len, new width=${WIDTHS[$j]}"
        else
            local len=$(echo -n "$display_value" | sed 's/\x1B\[[0-9;]*m//g' | wc -c)
            # Don't decrease length - we need the actual character count
            local padded_width=$((len + (2 * ${PADDINGS[$j]})))
            [[ $padded_width -gt ${WIDTHS[$j]} ]] && WIDTHS[$j]=$padded_width
            debug_log "Plain value: len=$len, new width=${WIDTHS[$j]}"
        fi
        
        # Update totals
        update_totals "$j" "$value" "${DATATYPES[$j]}" "${TOTALS[$j]}"
    done
    
    [[ $line_count -gt $MAX_LINES ]] && MAX_LINES=$line_count
    done
    
    debug_log "Final column widths: ${WIDTHS[*]}"
    debug_log "Max lines per row: $MAX_LINES"
    debug_log "Total rows to render: ${#ROW_JSONS[@]}"
}

# update_totals: Update totals for a column
# Args: column_index, value, datatype, total_type
update_totals() {
    local j="$1" value="$2" datatype="$3" total_type="$4"
    
    case "$total_type" in
        sum)
            if [[ "$datatype" == "kcpu" && "$value" =~ ^[0-9]+m$ ]]; then
                SUM_TOTALS[$j]=$(( ${SUM_TOTALS[$j]:-0} + ${value%m} ))
            elif [[ "$datatype" == "kmem" ]]; then
                if [[ "$value" =~ ^[0-9]+M$ ]]; then
                    SUM_TOTALS[$j]=$(( ${SUM_TOTALS[$j]:-0} + ${value%M} ))
                elif [[ "$value" =~ ^[0-9]+G$ ]]; then
                    SUM_TOTALS[$j]=$(( ${SUM_TOTALS[$j]:-0} + ${value%G} * 1000 ))
                elif [[ "$value" =~ ^[0-9]+K$ ]]; then
                    SUM_TOTALS[$j]=$(( ${SUM_TOTALS[$j]:-0} + ${value%K} / 1000 ))
                elif [[ "$value" =~ ^[0-9]+Mi$ ]]; then
                    SUM_TOTALS[$j]=$(( ${SUM_TOTALS[$j]:-0} + ${value%Mi} ))
                elif [[ "$value" =~ ^[0-9]+Gi$ ]]; then
                    SUM_TOTALS[$j]=$(( ${SUM_TOTALS[$j]:-0} + ${value%Gi} * 1000 ))
                fi
            elif [[ "$datatype" == "int" || "$datatype" == "float" ]]; then
                if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    SUM_TOTALS[$j]=$(awk "BEGIN {print (${SUM_TOTALS[$j]:-0} + $value)}")
                fi
            fi
            ;;
        min)
            if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                if [[ -z "${MIN_TOTALS[$j]}" || $(awk "BEGIN {print $value < ${MIN_TOTALS[$j]}}") -eq 1 ]]; then
                    MIN_TOTALS[$j]="$value"
                fi
            fi
            ;;
        max)
            if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                if [[ -z "${MAX_TOTALS[$j]}" || $(awk "BEGIN {print $value > ${MAX_TOTALS[$j]}}") -eq 1 ]]; then
                    MAX_TOTALS[$j]="$value"
                fi
            fi
            ;;
        count)
            if [[ -n "$value" && "$value" != "null" ]]; then
                COUNT_TOTALS[$j]=$(( ${COUNT_TOTALS[$j]:-0} + 1 ))
            fi
            ;;
        unique)
            [[ -n "$value" && "$value" != "null" ]] && UNIQUE_VALUES[$j]+=" $value"
            ;;
    esac
}

# render_table_top_border: Render the top border of the table
render_table_top_border() {
    debug_log "Rendering top border"
    
    printf "${THEME[border_color]}${THEME[tl_corner]}"
    for ((i=0; i<COLUMN_COUNT; i++)); do
        printf "${THEME[h_line]}%.0s" $(seq 1 ${WIDTHS[$i]})
        [[ $i -lt $((COLUMN_COUNT-1)) ]] && printf "${THEME[t_junct]}"
    done
    printf "${THEME[tr_corner]}${THEME[text_color]}\n"
}

# render_table_headers: Render the table headers row
render_table_headers() {
    debug_log "Rendering table headers"
    
    printf "${THEME[border_color]}${THEME[v_line]}${THEME[text_color]}"
    for ((i=0; i<COLUMN_COUNT; i++)); do
        debug_log "Rendering header $i: ${HEADERS[$i]}, width=${WIDTHS[$i]}, justification=${JUSTIFICATIONS[$i]}"
        
        case "${JUSTIFICATIONS[$i]}" in
            right)
                # Total available width minus padding on both sides
                local content_width=$((WIDTHS[$i] - (2 * PADDINGS[$i])))
                printf "%*s${THEME[header_color]}%*s${THEME[text_color]}%*s${THEME[border_color]}${THEME[v_line]}${THEME[text_color]}" \
                      "${PADDINGS[$i]}" "" "${content_width}" "${HEADERS[$i]}" "${PADDINGS[$i]}" ""
                ;;
            center)
                local content_width=$((WIDTHS[$i] - (2 * PADDINGS[$i])))
                local header_spaces=$(( (content_width - ${#HEADERS[$i]}) / 2 ))
                local left_spaces=$(( PADDINGS[$i] + header_spaces ))
                local right_spaces=$(( PADDINGS[$i] + content_width - ${#HEADERS[$i]} - header_spaces ))
                printf "%*s${THEME[header_color]}%s${THEME[text_color]}%*s${THEME[border_color]}${THEME[v_line]}${THEME[text_color]}" \
                      "${left_spaces}" "" "${HEADERS[$i]}" "${right_spaces}" ""
                ;;
            *)
                printf "%*s${THEME[header_color]}%-*s${THEME[text_color]}%*s${THEME[border_color]}${THEME[v_line]}${THEME[text_color]}" \
                      "${PADDINGS[$i]}" "" "$((WIDTHS[$i] - (2 * PADDINGS[$i])))" "${HEADERS[$i]}" "${PADDINGS[$i]}" ""
                ;;
        esac
    done
    printf "\n"
}

# render_table_separator: Render a separator line in the table
# Args: type (middle/bottom)
render_table_separator() {
    local type="$1"
    debug_log "Rendering table separator: $type"
    
    local left_char="${THEME[l_junct]}" right_char="${THEME[r_junct]}" middle_char="${THEME[cross]}"
    [[ "$type" == "bottom" ]] && left_char="${THEME[bl_corner]}" && right_char="${THEME[br_corner]}" && middle_char="${THEME[b_junct]}"
    
    printf "${THEME[border_color]}${left_char}"
    for ((i=0; i<COLUMN_COUNT; i++)); do
        # Ensure we have the correct number of horizontal line characters for each column width
        local width=${WIDTHS[$i]}
        for ((j=0; j<width; j++)); do
            printf "${THEME[h_line]}"
        done
        [[ $i -lt $((COLUMN_COUNT-1)) ]] && printf "${middle_char}"
    done
    printf "${right_char}${THEME[text_color]}\n"
}

# format_display_value: Format a cell value for display
# Args: value, null_value, zero_value, datatype, format, string_limit, wrap_mode, wrap_char
# Returns: formatted display value
format_display_value() {
    local value="$1" null_value="$2" zero_value="$3" datatype="$4" format="$5" string_limit="$6" wrap_mode="$7" wrap_char="$8"
    
    local validate_fn="${DATATYPE_HANDLERS[${datatype}_validate]}" format_fn="${DATATYPE_HANDLERS[${datatype}_format]}"
    value=$("$validate_fn" "$value")
    local display_value=$("$format_fn" "$value" "$format" "$string_limit" "$wrap_mode" "$wrap_char")
    
    if [[ "$value" == "null" ]]; then
        case "$null_value" in
            0) display_value="0" ;;
            missing) display_value="Missing" ;;
            *) display_value="" ;;
        esac
    elif [[ "$value" == "0" || "$value" == "0m" || "$value" == "0M" || "$value" == "0G" || "$value" == "0K" ]]; then
        case "$zero_value" in
            0) display_value="0" ;;
            missing) display_value="Missing" ;;
            *) display_value="" ;;
        esac
    fi
    
    echo "$display_value"
}

# render_data_rows: Render the data rows of the table
# Args: max_lines
render_data_rows() {
    local max_lines="$1"
    debug_log "================ RENDERING DATA ROWS ================"
    debug_log "Rendering ${#ROW_JSONS[@]} rows with max_lines=$max_lines"
    debug_log "Number of columns when rendering: $COLUMN_COUNT"
    debug_log "Column headers when rendering: ${HEADERS[*]}"
    
    # Initialize last break values
    local last_break_values=()
    for ((j=0; j<COLUMN_COUNT; j++)); do
        last_break_values[$j]=""
    done
    
    # Process each row in order
    for ((row_idx=0; row_idx<${#ROW_JSONS[@]}; row_idx++)); do
        local row_json="${ROW_JSONS[$row_idx]}"
        debug_log "Rendering row $row_idx: $row_json"
        
        # Check if we need a break
        local needs_break=false
        for ((j=0; j<COLUMN_COUNT; j++)); do
            if [[ "${BREAKS[$j]}" == "true" ]]; then
                local key="${KEYS[$j]}" value
                value=$(jq -r ".${key} // \"\"" <<<"$row_json")
                if [[ -n "${last_break_values[$j]}" && "$value" != "${last_break_values[$j]}" ]]; then
                    needs_break=true
                    debug_log "Break detected for column $j: '${last_break_values[$j]}' -> '$value'"
                    break
                fi
            fi
        done
        
        if [[ "$needs_break" == "true" ]]; then
            render_table_separator "middle"
        fi
        
        # Prepare values for all lines
        local -A line_values
        local row_line_count=1
        for ((j=0; j<COLUMN_COUNT; j++)); do
            local key="${KEYS[$j]}" value
            value=$(jq -r ".${key} // null" <<<"$row_json")
            debug_log "Row $row_idx, Column $j (${HEADERS[$j]}): Raw value='$value'"
            
            local display_value=$(format_display_value "$value" "${NULL_VALUES[$j]}" "${ZERO_VALUES[$j]}" "${DATATYPES[$j]}" "${FORMATS[$j]}" "${STRING_LIMITS[$j]}" "${WRAP_MODES[$j]}" "${WRAP_CHARS[$j]}")
            debug_log "Row $row_idx, Column $j (${HEADERS[$j]}): Display value='$display_value'"
            
            if [[ -n "${WRAP_CHARS[$j]}" && "${WRAP_MODES[$j]}" == "wrap" && -n "$display_value" && "$value" != "null" ]]; then
                local IFS="${WRAP_CHARS[$j]}"
                read -ra parts <<<"$display_value"
                debug_log "Wrapping value into ${#parts[@]} parts"
                for k in "${!parts[@]}"; do
                    line_values[$j,$k]="${parts[k]}"
                    debug_log "Row $row_idx, Column $j, Line $k: '${parts[k]}'"
                done
                # Track the maximum number of lines needed for this row
                [[ ${#parts[@]} -gt $row_line_count ]] && row_line_count=${#parts[@]}
            else
                line_values[$j,0]="$display_value"
                debug_log "Row $row_idx, Column $j, Line 0: '$display_value'"
            fi
        done
        
        debug_log "Row $row_idx needs $row_line_count lines"
        
        # Render each line of the row, but only up to the number of lines needed for this specific row
        for ((line=0; line<row_line_count; line++)); do
            debug_log "Rendering row $row_idx, line $line"
            printf "${THEME[border_color]}${THEME[v_line]}${THEME[text_color]}"
            for ((j=0; j<COLUMN_COUNT; j++)); do
                local display_value="${line_values[$j,$line]:-}"
                debug_log "Cell value for row $row_idx, column $j, line $line: '$display_value'"
                
                case "${JUSTIFICATIONS[$j]}" in
                    right)
                        # For right-justified text, calculate exact content space needed
                        local content_width=$((WIDTHS[$j] - (2 * PADDINGS[$j])))
                        # Use full column width regardless of whether display_value is empty
                        printf "%*s%*s%*s${THEME[border_color]}${THEME[v_line]}${THEME[text_color]}" \
                              "${PADDINGS[$j]}" "" "${content_width}" "$display_value" "${PADDINGS[$j]}" ""
                        ;;
                    center)
                        local content_width=$((WIDTHS[$j] - (2 * PADDINGS[$j])))
                        if [[ -z "$display_value" ]]; then
                            # For empty cells, just pad to full width
                            printf "%*s%*s${THEME[border_color]}${THEME[v_line]}${THEME[text_color]}" \
                                  "${PADDINGS[$j]}" "" "$((WIDTHS[$j] - (2 * PADDINGS[$j]) + PADDINGS[$j]))" ""
                        else
                            # For cells with content, center the text
                            local value_spaces=$(( (content_width - ${#display_value}) / 2 ))
                            local left_spaces=$(( PADDINGS[$j] + value_spaces ))
                            local right_spaces=$(( PADDINGS[$j] + content_width - ${#display_value} - value_spaces ))
                            printf "%*s%s%*s${THEME[border_color]}${THEME[v_line]}${THEME[text_color]}" \
                                  "${left_spaces}" "" "$display_value" "${right_spaces}" ""
                        fi
                        ;;
                    *)
                        # For left-justified text, ensure we use the full column width
                        printf "%*s%-*s%*s${THEME[border_color]}${THEME[v_line]}${THEME[text_color]}" \
                              "${PADDINGS[$j]}" "" "$((WIDTHS[$j] - (2 * PADDINGS[$j])))" "$display_value" "${PADDINGS[$j]}" ""
                        ;;
                esac
            done
            printf "\n"
        done
        
        # Update break values for the next iteration
        for ((j=0; j<COLUMN_COUNT; j++)); do
            if [[ "${BREAKS[$j]}" == "true" ]]; then
                local key="${KEYS[$j]}" value
                value=$(jq -r ".${key} // \"\"" <<<"$row_json")
                last_break_values[$j]="$value"
            fi
        done
    done
}

# render_totals_row: Render the totals row if any totals are defined
# Returns: 0 if totals were rendered, 1 otherwise
render_totals_row() {
    debug_log "Checking if totals row should be rendered"
    
    # Check if any totals are defined
    local has_totals=false
    for ((i=0; i<COLUMN_COUNT; i++)); do
        [[ "${TOTALS[$i]}" != "none" ]] && has_totals=true && break
    done
    
    if [[ "$has_totals" == true ]]; then
        debug_log "Rendering totals row"
        render_table_separator "middle"
        
        printf "${THEME[border_color]}${THEME[v_line]}${THEME[text_color]}"
        for ((i=0; i<COLUMN_COUNT; i++)); do
            local total_value="" datatype="${DATATYPES[$i]}" format="${FORMATS[$i]}"
            case "${TOTALS[$i]}" in
                sum)
                    if [[ -n "${SUM_TOTALS[$i]}" && "${SUM_TOTALS[$i]}" != "0" ]]; then
                        if [[ "$datatype" == "kcpu" ]]; then
                            total_value="${SUM_TOTALS[$i]}m"
                        elif [[ "$datatype" == "kmem" ]]; then
                            total_value="${SUM_TOTALS[$i]}M"
                        elif [[ "$datatype" == "int" || "$datatype" == "float" ]]; then
                            total_value="${SUM_TOTALS[$i]}"
                            [[ -n "$format" ]] && total_value=$(printf "$format" "$total_value")
                        fi
                    fi
                    ;;
                min)
                    total_value="${MIN_TOTALS[$i]:-}"
                    [[ -n "$format" ]] && total_value=$(printf "$format" "$total_value")
                    ;;
                max)
                    total_value="${MAX_TOTALS[$i]:-}"
                    [[ -n "$format" ]] && total_value=$(printf "$format" "$total_value")
                    ;;
                count)
                    total_value="${COUNT_TOTALS[$i]:-0}"
                    ;;
                unique)
                    if [[ -n "${UNIQUE_VALUES[$i]}" ]]; then
                        total_value=$(echo "${UNIQUE_VALUES[$i]}" | tr ' ' '\n' | sort -u | wc -l | awk '{print $1}')
                    else
                        total_value="0"
                    fi
                    ;;
            esac
            
            debug_log "Total for column $i (${HEADERS[$i]}, ${TOTALS[$i]}): $total_value"
            
            case "${JUSTIFICATIONS[$i]}" in
                right)
                    local content_width=$((WIDTHS[$i] - (2 * PADDINGS[$i])))
                    printf "%*s%*s%*s${THEME[border_color]}${THEME[v_line]}${THEME[text_color]}" \
                          "${PADDINGS[$i]}" "" "${content_width}" "$total_value" "${PADDINGS[$i]}" ""
                    ;;
                center)
                    local content_width=$((WIDTHS[$i] - (2 * PADDINGS[$i])))
                    local value_spaces=$(( (content_width - ${#total_value}) / 2 ))
                    local left_spaces=$(( PADDINGS[$i] + value_spaces ))
                    local right_spaces=$(( PADDINGS[$i] + content_width - ${#total_value} - value_spaces ))
                    printf "%*s%s%*s${THEME[border_color]}${THEME[v_line]}${THEME[text_color]}" \
                          "${left_spaces}" "" "$total_value" "${right_spaces}" ""
                    ;;
                *)
                    printf "%*s%-*s%*s${THEME[border_color]}${THEME[v_line]}${THEME[text_color]}" \
                          "${PADDINGS[$i]}" "" "$((WIDTHS[$i] - (2 * PADDINGS[$i])))" "$total_value" "${PADDINGS[$i]}" ""
                    ;;
            esac
        done
        printf "\n"
        
        render_table_separator "bottom"
        return 0
    fi
    
    debug_log "No totals to render"
    return 1
}

# draw_table: Main function to render a table from JSON layout and data
# Args: layout_json_file, data_json_file, [--debug], [--version]
# Outputs: ASCII table to stdout, errors/debug to stderr
draw_table() {
    local layout_file="$1" data_file="$2" debug=false
    shift 2
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --debug) debug=true; shift ;;
            --version) echo "tables.sh version $VERSION"; return 0 ;;
            *) echo -e "${THEME[border_color]}Error: Unknown option: $1${THEME[text_color]}" >&2; return 1 ;;
        esac
    done

    # Set debug flag
    DEBUG_FLAG="$debug"
    debug_log "Starting table rendering with debug=$debug"
    debug_log "Layout file: $layout_file"
    debug_log "Data file: $data_file"

    # Validate input files
    validate_input_files "$layout_file" "$data_file" || return 1
    
    # Parse layout JSON and set the theme
    parse_layout_file "$layout_file" || return 1
    get_theme "$THEME_NAME"
    
    # Initialize totals storage
    initialize_totals
    
    # Read and prepare data
    local data_json
    data_json=$(prepare_data "$data_file")
    
    # Sort data if specified
    local sorted_data
    sorted_data=$(sort_data "$data_json")
    
    # Process data rows, update widths and calculate totals
    process_data_rows "$sorted_data"
    
    debug_log "================ RENDERING TABLE ================"
    debug_log "Final column widths: ${WIDTHS[*]}"
    debug_log "Max lines per row: $MAX_LINES"
    debug_log "Total rows to render: ${#ROW_JSONS[@]}"
    
    # Render the table
    render_table_top_border
    render_table_headers
    render_table_separator "middle"
    render_data_rows "$MAX_LINES"
    
    # Render totals row if needed, otherwise render bottom border
    if ! render_totals_row; then
        render_table_separator "bottom"
    fi
    
    debug_log "Table rendering complete"
}

# Main: Call draw_table with all arguments
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    draw_table "$@"
fi