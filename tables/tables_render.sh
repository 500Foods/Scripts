# get_display_length: Get display length of text, ignoring ANSI escape sequences
get_display_length() {
    local text="$1"
    # Remove ANSI escape sequences using sed (faster than multiple bash substitutions)
    local clean_text
    clean_text=$(echo -n "$text" | sed 's/\x1B\[[0-9;]*[mK]//g')
    echo "${#clean_text}"
}

# format_with_commas: Add thousands separators to numbers (faster than awk)
format_with_commas() {
    local num="$1"
    # Use bash parameter expansion to add commas
    local result="$num"
    while [[ $result =~ ^([0-9]+)([0-9]{3}) ]]; do
        result="${BASH_REMATCH[1]},${BASH_REMATCH[2]}"
    done
    echo "$result"
}

# calculate_table_width: Calculate total table width including visible columns and separators
calculate_table_width() {
    local total_table_width=0 visible_count=0
    for ((i=0; i<COLUMN_COUNT; i++)); do
        if [[ "${VISIBLES[i]}" == "true" ]]; then
            ((total_table_width += WIDTHS[i])); ((visible_count++))
        fi
    done
    [[ $visible_count -gt 1 ]] && ((total_table_width += visible_count - 1))
    echo "$total_table_width"
}

# clip_text: Clip text to fit within specified width based on justification
clip_text() {
    local text="$1" width="$2" justification="$3"
    if [[ ${#text} -le $width ]]; then
        echo "$text"
        return
    fi
    case "$justification" in
        right) echo "${text: -${width}}" ;;
        center) local excess=$(( ${#text} - width )); local left_clip=$(( excess / 2 )); echo "${text:${left_clip}:${width}}" ;;
        *) echo "${text:0:${width}}" ;;
    esac
}

# render_cell: Render a single cell with proper alignment and colors
render_cell() {
    local content="$1" width="$2" padding="$3" justification="$4" color="$5"
    local content_width=$((width - (2 * padding)))
    case "$justification" in
        right) printf "%*s${color}%*s${THEME[text_color]}%*s${THEME[border_color]}${THEME[v_line]}${THEME[text_color]}" "$padding" "" "$content_width" "$content" "$padding" "" ;;
        center) local spaces=$(( (content_width - ${#content}) / 2 )); local left_spaces=$(( padding + spaces )); local right_spaces=$(( padding + content_width - ${#content} - spaces )); printf "%*s${color}%s${THEME[text_color]}%*s${THEME[border_color]}${THEME[v_line]}${THEME[text_color]}" "$left_spaces" "" "$content" "$right_spaces" "" ;;
        *) printf "%*s${color}%-*s${THEME[text_color]}%*s${THEME[border_color]}${THEME[v_line]}${THEME[text_color]}" "$padding" "" "$content_width" "$content" "$padding" "" ;;
    esac
}

# render_table_element: Unified function to render title or footer
render_table_element() {
    local element_type="$1" total_table_width="$2"
    local element_text element_position element_width color_theme
    
    if [[ "$element_type" == "title" ]]; then
        [[ -z "$TABLE_TITLE" ]] && return
        element_text=$(eval echo "$TABLE_TITLE" 2>/dev/null)
        element_position="$TITLE_POSITION"
        calculate_title_width "$element_text" "$total_table_width"
        element_width="$TITLE_WIDTH"
        color_theme="${THEME[header_color]}"
    else
        [[ -z "$TABLE_FOOTER" ]] && return
        element_text=$(eval echo "$TABLE_FOOTER" 2>/dev/null)
        element_position="$FOOTER_POSITION"
        calculate_footer_width "$element_text" "$total_table_width"
        element_width="$FOOTER_WIDTH"
        color_theme="${THEME[footer_color]}"
    fi
    
    local offset=0
    case "$element_position" in
        left) offset=0 ;;
        right) offset=$((total_table_width - element_width)) ;;
        center) offset=$(((total_table_width - element_width) / 2)) ;;
        full) offset=0 ;;
        *) offset=0 ;;
    esac
    
    if [[ "$element_type" == "title" ]]; then
        [[ $offset -gt 0 ]] && printf "%*s" "$offset" ""
        printf "${THEME[border_color]}%s" "${THEME[tl_corner]}"
        printf "${THEME[h_line]}%.0s" $(seq 1 "$element_width")
        printf "%s${THEME[text_color]}\n" "${THEME[tr_corner]}"
    fi
    
    [[ $offset -gt 0 ]] && printf "%*s" "$offset" ""
    printf "${THEME[border_color]}%s${THEME[text_color]}" "${THEME[v_line]}"
    
    local available_width=$((element_width - (2 * DEFAULT_PADDING)))
    element_text=$(clip_text "$element_text" "$available_width" "$element_position")
    
    case "$element_position" in
        left) printf "%*s${color_theme}%-*s${THEME[text_color]}%*s" "$DEFAULT_PADDING" "" "$available_width" "$element_text" "$DEFAULT_PADDING" "" ;;
        right) printf "%*s${color_theme}%*s${THEME[text_color]}%*s" "$DEFAULT_PADDING" "" "$available_width" "$element_text" "$DEFAULT_PADDING" "" ;;
        center) printf "%*s${color_theme}%s${THEME[text_color]}%*s" "$DEFAULT_PADDING" "" "$element_text" "$((available_width - ${#element_text} + DEFAULT_PADDING))" "" ;;
        full) local text_len=${#element_text}; local spaces=$(( (available_width - text_len) / 2 )); local left_spaces=$(( DEFAULT_PADDING + spaces )); local right_spaces=$(( DEFAULT_PADDING + available_width - text_len - spaces )); printf "%*s${color_theme}%s${THEME[text_color]}%*s" "$left_spaces" "" "$element_text" "$right_spaces" "" ;;
        *) printf "%*s${color_theme}%s${THEME[text_color]}%*s" "$DEFAULT_PADDING" "" "$element_text" "$DEFAULT_PADDING" "" ;;
    esac
    printf "${THEME[border_color]}%s${THEME[text_color]}\n" "${THEME[v_line]}"
    
    if [[ "$element_type" == "footer" ]]; then
        [[ $offset -gt 0 ]] && printf "%*s" "$offset" ""
        echo -ne "${THEME[border_color]}${THEME[bl_corner]}"
        for i in $(seq 1 "$element_width"); do echo -ne "${THEME[h_line]}"; done
        echo -ne "${THEME[br_corner]}${THEME[text_color]}\n"
    fi
}

render_table_title() {
    render_table_element "title" "$1"
}


# render_table_border: Optimized border rendering with pre-calculated characters
render_table_border() {
    local border_type="$1" total_table_width="$2" element_offset="$3" element_right_edge="$4" element_width="$5"
    local column_widths_sum=0 column_positions=()
    
    # Calculate column positions
    for ((i=0; i<COLUMN_COUNT-1; i++)); do
        if [[ "${VISIBLES[i]}" == "true" ]]; then
            column_widths_sum=$((column_widths_sum + WIDTHS[i]))
            local has_more_visible=false
            for ((j=$((i+1)); j<COLUMN_COUNT; j++)); do
                [[ "${VISIBLES[j]}" == "true" ]] && has_more_visible=true && break
            done
            [[ "$has_more_visible" == "true" ]] && column_positions+=("$column_widths_sum") && ((column_widths_sum++))
        fi
    done
    
    # Calculate maximum width
    local max_width=$((total_table_width + 2))
    if [[ -n "$element_width" && $element_width -gt 0 ]]; then
        local adjusted_element_width=$((element_width + 2))
        [[ $adjusted_element_width -gt $max_width ]] && max_width=$adjusted_element_width
    fi
    
    # Pre-build the entire border string for performance
    local border_string=""
    local left_char right_char junction_char
    
    # Determine corner and junction characters based on border type
    if [[ "$border_type" == "top" ]]; then
        left_char="${THEME[tl_corner]}"
        right_char="${THEME[tr_corner]}"
        junction_char="${THEME[t_junct]}"
    else
        left_char="${THEME[bl_corner]}"
        right_char="${THEME[br_corner]}"
        junction_char="${THEME[b_junct]}"
    fi
    
    # Handle element positioning adjustments
    if [[ -n "$element_width" && $element_width -gt 0 && $element_offset -eq 0 ]]; then
        left_char="${THEME[l_junct]}"
    fi
    
    # Build border string character by character
    for ((i=0; i<max_width; i++)); do
        local char_to_print="${THEME[h_line]}"
        
        if [[ $i -eq 0 ]]; then
            char_to_print="$left_char"
        elif [[ $i -eq $((max_width - 1)) ]]; then
            if [[ -n "$element_width" && $element_width -gt 0 && $element_right_edge -gt $total_table_width ]]; then
                char_to_print="${THEME[$([[ "$border_type" == "top" ]] && echo "br_corner" || echo "tr_corner")]}"
            elif [[ -n "$element_width" && $element_width -gt 0 && $element_right_edge -eq $total_table_width ]]; then
                char_to_print="${THEME[r_junct]}"
            else
                char_to_print="$right_char"
            fi
        else
            # Check for column separators
            for pos in "${column_positions[@]}"; do
                if [[ $((pos + 1)) -eq $i ]]; then
                    char_to_print="$junction_char"
                    break
                fi
            done
            
            # Check for element boundaries
            if [[ -n "$element_width" && $element_width -gt 0 ]]; then
                if [[ $i -eq $element_offset && $element_offset -gt 0 && $element_offset -lt $((total_table_width + 1)) ]]; then
                    char_to_print="${THEME[$([[ "$border_type" == "top" ]] && echo "b_junct" || echo "t_junct")]}"
                elif [[ $i -eq $((element_right_edge + 1)) && $((element_right_edge + 1)) -lt $((total_table_width + 1)) ]]; then
                    char_to_print="${THEME[$([[ "$border_type" == "top" ]] && echo "b_junct" || echo "t_junct")]}"
                elif [[ $i -eq $((total_table_width + 1)) && $i -lt $((max_width - 1)) && $element_right_edge -gt $((total_table_width - 1)) ]]; then
                    char_to_print="${THEME[$([[ "$border_type" == "top" ]] && echo "t_junct" || echo "b_junct")]}"
                fi
            fi
        fi
        
        border_string+="$char_to_print"
    done
    
    # Output the complete border in one operation
    printf "${THEME[border_color]}%s${THEME[text_color]}\n" "$border_string"
}

# render_table_top_border: Render the top border of the table
render_table_top_border() {
    local total_table_width
    total_table_width=$(calculate_table_width)
    local title_offset=0 title_right_edge=0 title_width="" title_position="none"
    if [[ -n "$TABLE_TITLE" ]]; then
        title_width=$TITLE_WIDTH; title_position=$TITLE_POSITION
        case "$TITLE_POSITION" in
            left) title_offset=0; title_right_edge=$TITLE_WIDTH ;;
            right) title_offset=$((total_table_width - TITLE_WIDTH)); title_right_edge=$total_table_width ;;
            center) title_offset=$(((total_table_width - TITLE_WIDTH) / 2)); title_right_edge=$((title_offset + TITLE_WIDTH)) ;;
            full) title_offset=0; title_right_edge=$total_table_width ;;
            *) title_offset=0; title_right_edge=$TITLE_WIDTH ;;
        esac
    fi
    render_table_border "top" "$total_table_width" "$title_offset" "$title_right_edge" "$title_width" "$title_position" "$([[ "$title_position" == "full" ]] && echo true || echo false)"
}

# render_table_bottom_border: Render the bottom border of the table
render_table_bottom_border() {
    local total_table_width
    total_table_width=$(calculate_table_width)
    local footer_offset=0 footer_right_edge=0 footer_width="" footer_position="none"
    if [[ -n "$TABLE_FOOTER" ]]; then
        calculate_footer_width "$TABLE_FOOTER" "$total_table_width"
        footer_width=$FOOTER_WIDTH; footer_position=$FOOTER_POSITION
        case "$FOOTER_POSITION" in
            left) footer_offset=0; footer_right_edge=$FOOTER_WIDTH ;;
            right) footer_offset=$((total_table_width - FOOTER_WIDTH)); footer_right_edge=$total_table_width ;;
            center) footer_offset=$(((total_table_width - FOOTER_WIDTH) / 2)); footer_right_edge=$((footer_offset + FOOTER_WIDTH)) ;;
            full) footer_offset=0; footer_right_edge=$total_table_width ;;
            *) footer_offset=0; footer_right_edge=$FOOTER_WIDTH ;;
        esac
    fi
    render_table_border "bottom" "$total_table_width" "$footer_offset" "$footer_right_edge" "$footer_width" "$footer_position" "$([[ "$footer_position" == "full" ]] && echo true || echo false)"
}

# render_table_headers: Render the table headers row
render_table_headers() {
    printf "${THEME[border_color]}%s${THEME[text_color]}" "${THEME[v_line]}"
    for ((i=0; i<COLUMN_COUNT; i++)); do
        local visible="${VISIBLES[i]}"
        if [[ "$visible" == "true" ]]; then
            local header_text="${HEADERS[$i]}" width="${WIDTHS[i]}" padding="${PADDINGS[i]}" justification="${JUSTIFICATIONS[$i]}"
            local content_width=$((width - (2 * padding)))
            header_text=$(clip_text "$header_text" "$content_width" "$justification")
            render_cell "$header_text" "$width" "$padding" "$justification" "${THEME[caption_color]}"
        fi
    done
    printf "\n"
}

# render_table_separator: Render a separator line in the table
render_table_separator() {
    local type="$1"
    local left_char="${THEME[l_junct]}" right_char="${THEME[r_junct]}" middle_char="${THEME[cross]}"
    [[ "$type" == "bottom" ]] && left_char="${THEME[bl_corner]}" && right_char="${THEME[br_corner]}" && middle_char="${THEME[b_junct]}"
    printf "${THEME[border_color]}%s" "${left_char}"
    for ((i=0; i<COLUMN_COUNT; i++)); do
        if [[ "${VISIBLES[i]}" == "true" ]]; then
            local width=${WIDTHS[i]}
            for ((j=0; j<width; j++)); do printf "%s" "${THEME[h_line]}"; done
            if [[ $i -lt $((COLUMN_COUNT-1)) ]]; then
                local next_visible=false
                for ((k=$((i+1)); k<COLUMN_COUNT; k++)); do
                    if [[ "${VISIBLES[k]}" == "true" ]]; then next_visible=true; break; fi
                done
                [[ "$next_visible" == "true" ]] && printf "%s" "${middle_char}"
            fi
        fi
    done
    printf "%s${THEME[text_color]}\n" "${right_char}"
}

# render_data_rows: Render the data rows of the table
render_data_rows() {
    local max_lines="$1"
    [[ ${#DATA_ROWS[@]} -eq 0 ]] && return
    local last_break_values=()
    for ((j=0; j<COLUMN_COUNT; j++)); do last_break_values[j]=""; done
    for ((row_idx=0; row_idx<${#DATA_ROWS[@]}; row_idx++)); do
        eval "${DATA_ROWS[$row_idx]}"
        # Check if we need a break
        local needs_break=false
        for ((j=0; j<COLUMN_COUNT; j++)); do
            if [[ "${BREAKS[$j]}" == "true" ]]; then
                local key="${KEYS[$j]}" value
                value="${row_data[$key]}"
                if [[ -n "${last_break_values[$j]}" && "$value" != "${last_break_values[$j]}" ]]; then
                    needs_break=true
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
            value="${row_data[$key]}"
            
            local display_value
            display_value=$(format_display_value "$value" "${NULL_VALUES[j]}" "${ZERO_VALUES[j]}" "${DATATYPES[j]}" "${FORMATS[j]}" "${STRING_LIMITS[j]}" "${WRAP_MODES[j]}" "${WRAP_CHARS[j]}")
            
            if [[ -n "${WRAP_CHARS[$j]}" && "${WRAP_MODES[$j]}" == "wrap" && -n "$display_value" && "$value" != "null" ]]; then
                local IFS="${WRAP_CHARS[$j]}"
                read -ra parts <<<"$display_value"
                for k in "${!parts[@]}"; do
                    local part="${parts[k]}"
                    local content_width=$((WIDTHS[j] - (2 * PADDINGS[j])))
                    if [[ ${#part} -gt $content_width ]]; then
                        case "${JUSTIFICATIONS[$j]}" in
                            right)
                                part="${part: -${content_width}}"
                                ;;
                            center)
                                local excess=$(( ${#part} - content_width ))
                                local left_clip=$(( excess / 2 ))
                                part="${part:${left_clip}:${content_width}}"
                                ;;
                            *)
                                part="${part:0:${content_width}}"
                                ;;
                        esac
                    fi
                    line_values[$j,$k]="$part"
                done
                [[ ${#parts[@]} -gt $row_line_count ]] && row_line_count=${#parts[@]}
            elif [[ "${WRAP_MODES[$j]}" == "wrap" && -n "$display_value" && "$value" != "null" ]]; then
                local content_width=$((WIDTHS[j] - (2 * PADDINGS[j])))
                local words=()
                IFS=' ' read -ra words <<<"$display_value"
                local current_line=""
                local line_index=0
                for word in "${words[@]}"; do
                    if [[ -z "$current_line" ]]; then
                        current_line="$word"
                    elif [[ $(( ${#current_line} + ${#word} + 1 )) -le $content_width ]]; then
                        current_line="$current_line $word"
                    else
                        line_values[$j,$line_index]="$current_line"
                        current_line="$word"
                        ((line_index++))
                    fi
                done
                if [[ -n "$current_line" ]]; then
                    line_values[$j,$line_index]="$current_line"
                    ((line_index++))
                fi
                [[ $line_index -gt $row_line_count ]] && row_line_count=$line_index
            else
                local content_width=$((WIDTHS[j] - (2 * PADDINGS[j])))
                if [[ ${#display_value} -gt $content_width ]]; then
                    case "${JUSTIFICATIONS[$j]}" in
                        right)
                            display_value="${display_value: -${content_width}}"
                            ;;
                        center)
                            local excess=$(( ${#display_value} - content_width ))
                            local left_clip=$(( excess / 2 ))
                            display_value="${display_value:${left_clip}:${content_width}}"
                            ;;
                        *)
                            display_value="${display_value:0:${content_width}}"
                            ;;
                    esac
                fi
                line_values[$j,0]="$display_value"
            fi
        done
        
        # Render each line of the row
        for ((line=0; line<row_line_count; line++)); do
            printf "${THEME[border_color]}%s${THEME[text_color]}" "${THEME[v_line]}"
            for ((j=0; j<COLUMN_COUNT; j++)); do
                if [[ "${VISIBLES[j]}" == "true" ]]; then
                    local display_value="${line_values[$j,$line]:-}"
                    local content_width=$((WIDTHS[j] - (2 * PADDINGS[j])))
                    
                    # Clip the display value if it exceeds the content width and a width is specified
                    if [[ ${#display_value} -gt $content_width && "${IS_WIDTH_SPECIFIED[j]}" == "true" ]]; then
                        case "${JUSTIFICATIONS[$j]}" in
                            right)
                                display_value="${display_value: -$content_width}"
                                ;;
                            center)
                                local excess=$(( ${#display_value} - content_width ))
                                local left_clip=$(( excess / 2 ))
                                display_value="${display_value:$left_clip:$content_width}"
                                ;;
                            *)
                                display_value="${display_value:0:$content_width}"
                                ;;
                        esac
                    fi
                    
                    render_cell "$display_value" "${WIDTHS[j]}" "${PADDINGS[j]}" "${JUSTIFICATIONS[j]}" "${THEME[text_color]}"
                fi
            done
            printf "\n"
        done
        
        # Update break values for the next iteration
        for ((j=0; j<COLUMN_COUNT; j++)); do
            if [[ "${BREAKS[$j]}" == "true" ]]; then
                local key="${KEYS[$j]}" value
                value="${row_data[$key]}"
                last_break_values[j]="$value"
            fi
        done
    done
}

render_table_footer() {
    render_table_element "footer" "$1"
}

# render_summaries_row: Render the summaries row if any summaries are defined
render_summaries_row() {
    local has_summaries=false
    for ((i=0; i<COLUMN_COUNT; i++)); do
        [[ "${SUMMARIES[$i]}" != "none" ]] && has_summaries=true && break
    done
    if [[ "$has_summaries" == true ]]; then
        render_table_separator "middle"
        
        printf "${THEME[border_color]}%s${THEME[text_color]}" "${THEME[v_line]}"
        for ((i=0; i<COLUMN_COUNT; i++)); do
            if [[ "${VISIBLES[i]}" == "true" ]]; then
                local summary_value="" datatype="${DATATYPES[$i]}" format="${FORMATS[$i]}"
                case "${SUMMARIES[$i]}" in
                    sum)
                        if [[ -n "${SUM_SUMMARIES[$i]}" && "${SUM_SUMMARIES[$i]}" != "0" ]]; then
                            if [[ "$datatype" == "kcpu" ]]; then
                                local formatted_num
                                formatted_num=$(format_with_commas "${SUM_SUMMARIES[$i]}")
                                summary_value="${formatted_num}m"
                            elif [[ "$datatype" == "kmem" ]]; then
                                local formatted_num
                                formatted_num=$(format_with_commas "${SUM_SUMMARIES[$i]}")
                                summary_value="${formatted_num}M"
                            elif [[ "$datatype" == "num" ]]; then
                                summary_value=$(format_num "${SUM_SUMMARIES[$i]}" "$format")
                            elif [[ "$datatype" == "int" || "$datatype" == "float" ]]; then
                                summary_value="${SUM_SUMMARIES[$i]}"
                                [[ -n "$format" ]] && summary_value=$(printf "%s" "$format" | xargs printf "%s" "$summary_value")
                            fi
                        fi
                        ;;
                    min)
                        summary_value="${MIN_SUMMARIES[$i]:-}"
                        [[ -n "$format" ]] && summary_value=$(printf "%s" "$format" | xargs printf "%s" "$summary_value")
                        ;;
                    max)
                        summary_value="${MAX_SUMMARIES[$i]:-}"
                        [[ -n "$format" ]] && summary_value=$(printf "%s" "$format" | xargs printf "%s" "$summary_value")
                        ;;
                    count)
                        summary_value="${COUNT_SUMMARIES[$i]:-0}"
                        ;;
                    unique)
                        if [[ -n "${UNIQUE_VALUES[$i]}" ]]; then
                            summary_value=$(echo "${UNIQUE_VALUES[$i]}" | tr ' ' '\n' | sort -u | wc -l)
                        else
                            summary_value="0"
                        fi
                        ;;
                    avg)
                        if [[ -n "${AVG_SUMMARIES[$i]}" && "${AVG_COUNTS[$i]}" -gt 0 ]]; then
                            local avg_result
                            # Use bash arithmetic for division (will be integer division, but good enough for most cases)
                            avg_result=$((${AVG_SUMMARIES[$i]} / ${AVG_COUNTS[$i]}))
                            
                            # Format based on datatype
                            if [[ "$datatype" == "int" ]]; then
                                summary_value=$(printf "%.0f" "$avg_result")
                            elif [[ "$datatype" == "float" ]]; then
                                # Use same decimal precision as format if available, otherwise 2 decimals
                                if [[ -n "$format" && "$format" =~ %.([0-9]+)f ]]; then
                                    local decimals="${BASH_REMATCH[1]}"
                                    summary_value=$(printf "%.${decimals}f" "$avg_result")
                                else
                                    summary_value=$(printf "%.2f" "$avg_result")
                                fi
                            elif [[ "$datatype" == "num" ]]; then
                                summary_value=$(format_num "$avg_result" "$format")
                            else
                                summary_value="$avg_result"
                            fi
                        else
                            summary_value="0"
                        fi
                        ;;
                esac
                
                # Use summary_color for all summary values and clip if necessary based on whether width is specified
                local content_width=$((WIDTHS[i] - (2 * PADDINGS[i])))
                if [[ ${#summary_value} -gt $content_width && "${IS_WIDTH_SPECIFIED[i]}" == "true" ]]; then
                    case "${JUSTIFICATIONS[$i]}" in
                        right)
                                summary_value="${summary_value: -$content_width}"
                            ;;
                        center)
                            local excess=$(( ${#summary_value} - content_width ))
                            local left_clip=$(( excess / 2 ))
                            summary_value="${summary_value:$left_clip:$content_width}"
                            ;;
                        *)
                            summary_value="${summary_value:0:$content_width}"
                            ;;
                    esac
                fi
                
                render_cell "$summary_value" "${WIDTHS[i]}" "${PADDINGS[i]}" "${JUSTIFICATIONS[i]}" "${THEME[summary_color]}"
            fi
        done
        printf "\n"
        return 0
    fi
    return 1
}
