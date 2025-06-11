# Tables Developer Documentation

This document provides detailed technical information about the internal workings of the `tables.sh` script and instructions for extending its functionality.

## Architecture Overview

The tables.sh script is organized into several functional components:

1. **Configuration System**: Parses and validates layout and data JSON files
2. **Theme System**: Manages visual appearance with customizable themes
3. **Datatype System**: Validates and formats different types of data
4. **Data Processing Pipeline**: Prepares, sorts, and processes data rows
5. **Rendering System**: Draws the table with borders, content, and totals

The script follows a modular design with clearly defined functions for each component, making it extensible without requiring significant changes to the core code.

## Core Components and Flow

The main execution flow follows these steps:

1. Parse arguments and validate input files
2. Parse layout JSON and set theme
3. Initialize totals storage
4. Read and prepare data
5. Sort data if specified
6. Process data rows, update column widths, calculate totals
7. Render the table (borders, headers, data rows, totals)

Here's a visualization of the data flow:

```
Input JSON Files
       ↓
Configuration Parsing
       ↓
  Theme Setup
       ↓
 Data Processing ←→ Datatype System
       ↓
 Width Calculation
       ↓
  Table Rendering
       ↓
    Output
```

## Theme System

The theme system defines the visual appearance of tables, including colors and border characters.

### Theme Structure

Each theme is stored as an associative array with the following keys:

```bash
declare -A THEME_NAME=(
    [border_color]='ANSI color code'
    [header_color]='ANSI color code'
    [text_color]='ANSI color code'
    [tl_corner]='character'  # Top-left corner
    [tr_corner]='character'  # Top-right corner
    [bl_corner]='character'  # Bottom-left corner
    [br_corner]='character'  # Bottom-right corner
    [h_line]='character'     # Horizontal line
    [v_line]='character'     # Vertical line
    [t_junct]='character'    # Top junction
    [b_junct]='character'    # Bottom junction
    [l_junct]='character'    # Left junction
    [r_junct]='character'    # Right junction
    [cross]='character'      # Cross junction
)
```

### Adding a New Theme

To add a new theme, follow these steps:

1. Define a new associative array with all required theme elements:

```bash
declare -A GREEN_THEME=(
    [border_color]='\033[0;32m' # Green border color
    [header_color]='\033[0;32m' # Green header color
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
```

2. Update the `get_theme` function to support your new theme:

```bash
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
        green)  # Add your new theme case here
            for key in "${!GREEN_THEME[@]}"; do
                THEME[$key]="${GREEN_THEME[$key]}"
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
```

3. Test your new theme by specifying it in the layout JSON:

```json
{
  "theme": "Green",
  "columns": [
    ...
  ]
}
```

## Datatype System

The datatype system manages how different types of data are validated, formatted, and totaled.

### Datatype Registry

The script uses a registry pattern to map datatypes to their respective functions:

```bash
declare -A DATATYPE_HANDLERS=(
    [text_validate]="validate_text"
    [text_format]="format_text"
    [text_total_types]="count unique"
    [int_validate]="validate_number"
    [int_format]="format_number"
    [int_total_types]="sum min max count unique"
    # Other datatype handlers...
)
```

For each datatype, three entries are registered:
- `datatype_validate`: Function to validate input values
- `datatype_format`: Function to format values for display
- `datatype_total_types`: Space-separated list of supported total types

### Adding a New Datatype

To add a new datatype, follow these steps:

1. Define validation and formatting functions:

```bash
# Example: Adding a "percentage" datatype

# Validation function
validate_percentage() {
    local value="$1"
    if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?%$ ]] || [[ "$value" == "0%" ]] || [[ "$value" == "null" ]]; then
        echo "$value"
    else
        echo ""
    fi
}

# Formatting function
format_percentage() {
    local value="$1" format="$2"
    [[ -z "$value" || "$value" == "null" || "$value" == "0%" ]] && { echo ""; return; }
    if [[ -n "$format" && "$value" =~ ^[0-9]+(\.[0-9]+)?%$ ]]; then
        local num_value=${value%\%}
        printf "$format" "$num_value"
    else
        echo "$value"
    fi
}
```

2. Update the datatype registry:

```bash
declare -A DATATYPE_HANDLERS=(
    # Existing handlers...
    [percentage_validate]="validate_percentage"
    [percentage_format]="format_percentage"
    [percentage_total_types]="sum min max count unique"
)
```

3. Test your new datatype by specifying it in the layout JSON:

```json
{
  "columns": [
    {
      "header": "COMPLETION",
      "key": "completion",
      "datatype": "percentage",
      "justification": "right"
    }
  ]
}
```

### Implementing Total Functions

For custom datatypes that need special handling for totals, you may need to update the `update_totals` function:

```bash
update_totals() {
    local j="$1" value="$2" datatype="$3" total_type="$4"
    
    case "$total_type" in
        sum)
            # Add handling for your custom datatype
            if [[ "$datatype" == "percentage" && "$value" =~ ^[0-9]+(\.[0-9]+)?%$ ]]; then
                # Extract numeric value without % sign
                local numeric_value=${value%\%}
                SUM_TOTALS[$j]=$(awk "BEGIN {print (${SUM_TOTALS[$j]:-0} + $numeric_value)}")
            }
            # Existing handlers...
            ;;
        # Other total types...
    esac
}
```

## Data Processing Pipeline

The data processing pipeline handles preparing, sorting, and processing data for display.

### Key Components

1. **prepare_data**: Reads and validates data from JSON
2. **sort_data**: Applies sorting based on configuration
3. **process_data_rows**: Processes rows, updates column widths, calculates totals
4. **update_totals**: Updates running totals for columns

### Extending Sorting Capabilities

To add more advanced sorting options:

1. Modify the `parse_sort_config` function to accept additional parameters:

```bash
parse_sort_config() {
    local sort_json="$1"
    debug_log "Parsing sort configuration"
    
    # Clear sort arrays
    SORT_KEYS=()
    SORT_DIRECTIONS=()
    SORT_PRIORITIES=()
    SORT_TYPES=()  # New array for sort types
    
    # Process sort configuration
    for ((i=0; i<sort_count; i++)); do
        local sort_item
        sort_item=$(jq -c ".[$i]" <<<"$sort_json")
        SORT_KEYS[$i]=$(jq -r '.key // ""' <<<"$sort_item")
        SORT_DIRECTIONS[$i]=$(jq -r '.direction // "asc"' <<<"$sort_item" | tr '[:upper:]' '[:lower:]')
        SORT_PRIORITIES[$i]=$(jq -r '.priority // 0' <<<"$sort_item")
        SORT_TYPES[$i]=$(jq -r '.type // "lexical"' <<<"$sort_item" | tr '[:upper:]' '[:lower:]')
        
        # Validate sort type
        if [[ "${SORT_TYPES[$i]}" != "lexical" && "${SORT_TYPES[$i]}" != "numeric" && "${SORT_TYPES[$i]}" != "version" ]]; then
            echo -e "${THEME[border_color]}Warning: Invalid sort type '${SORT_TYPES[$i]}' for key ${SORT_KEYS[$i]}, using 'lexical'${THEME[text_color]}" >&2
            SORT_TYPES[$i]="lexical"
        fi
    done
}
```

2. Update the `sort_data` function to use the new sort types:

```bash
sort_data() {
    local data_json="$1"
    debug_log "Sorting data"
    
    # Build sort expression based on sort types
    # This would require more complex sort logic...
}
```

## Rendering System

The rendering system draws the table with borders, headers, data rows, and totals.

### Key Components

1. **render_table_top_border**: Draws the top border
2. **render_table_headers**: Draws the header row
3. **render_table_separator**: Draws horizontal separators
4. **render_data_rows**: Draws the data rows
5. **render_totals_row**: Draws the totals row if needed

### Customizing Output Format

To modify the output format (e.g., to support HTML or CSV output), you would need to create new rendering functions and a switch to select the output format:

1. Add an output format parameter to the configuration:

```json
{
  "theme": "Red",
  "output_format": "ascii",  // or "html", "csv", etc.
  "columns": [
    ...
  ]
}
```

2. Create new rendering functions for each format:

```bash
render_table_html() {
    # HTML rendering logic
    echo "<table>"
    # ...
}

render_table_csv() {
    # CSV rendering logic
    # ...
}
```

3. Update the main flow to select the appropriate renderer:

```bash
draw_table() {
    # Existing code...
    
    # Get output format
    local output_format
    output_format=$(jq -r '.output_format // "ascii"' "$layout_file")
    
    # Render based on format
    case "$output_format" in
        ascii)
            render_table_top_border
            render_table_headers
            render_table_separator "middle"
            render_data_rows "$MAX_LINES"
            if ! render_totals_row; then
                render_table_separator "bottom"
            fi
            ;;
        html)
            render_table_html
            ;;
        csv)
            render_table_csv
            ;;
        *)
            echo -e "${THEME[border_color]}Error: Unknown output format '$output_format'${THEME[text_color]}" >&2
            return 1
            ;;
    esac
}
```

## Advanced Extension: Adding Column Calculations

To add calculated columns that derive values from other columns:

1. Extend the column configuration to support calculations:

```json
{
  "columns": [
    {
      "header": "TOTAL",
      "key": "calculated_total",
      "datatype": "float",
      "calculation": "price * quantity",
      "format": "%.2f"
    }
  ]
}
```

2. Add a calculation processor during data preparation:

```bash
process_calculations() {
    local row_json="$1"
    local result="$row_json"
    
    for ((j=0; j<COLUMN_COUNT; j++)); do
        local calculation="${CALCULATIONS[$j]}"
        if [[ -n "$calculation" ]]; then
            debug_log "Processing calculation for column $j: $calculation"
            
            # Replace column keys with their values
            local calc_expr="$calculation"
            for ((k=0; k<COLUMN_COUNT; k++)); do
                local key="${KEYS[$k]}"
                local value=$(jq -r ".${key} // \"0\"" <<<"$row_json")
                # Only use numeric values
                if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    calc_expr=${calc_expr//$key/$value}
                else
                    calc_expr=${calc_expr//$key/0}
                fi
            done
            
            # Evaluate the expression and store the result
            local calc_result=$(awk "BEGIN {print ($calc_expr)}")
            result=$(jq --arg key "${KEYS[$j]}" --arg val "$calc_result" '. + {($key): $val}' <<<"$result")
        fi
    done
    
    echo "$result"
}
```

3. Update the data processing to apply calculations:

```bash
process_data_rows() {
    local data_json="$1"
    
    # For each row...
    for ((i=0; i<row_count; i++)); do
        local row_json
        row_json=$(jq -c ".[$i]" <<<"$data_json")
        
        # Apply calculations
        row_json=$(process_calculations "$row_json")
        
        ROW_JSONS+=("$row_json")
        # Rest of processing...
    done
}
```

## Performance Optimization

For large datasets, consider these optimizations:

1. **Batched Processing**: Process data in batches instead of all at once
2. **Lazy Evaluation**: Only calculate values when needed
3. **Caching**: Cache calculated values and intermediate results
4. **Parallel Processing**: Use background processes for independent operations

Example of batched processing:

```bash
process_data_batched() {
    local data_file="$1" batch_size=100
    local row_count=$(jq '. | length' "$data_file")
    
    for ((i=0; i<row_count; i+=batch_size)); do
        local end=$((i+batch_size))
        [[ $end -gt $row_count ]] && end=$row_count
        
        jq -c ".[$i:$end]" "$data_file" | process_batch
    done
}
```

## Debugging and Testing

To debug and test new extensions:

1. Use the `--debug` flag to enable detailed logging:

```bash
./tables.sh layout.json data.json --debug
```

2. Create test cases for your extensions:

```bash
test_percentage_datatype() {
    cat > test_percentage_layout.json << 'EOF'
    {
      "columns": [
        {
          "header": "NAME",
          "key": "name",
          "datatype": "text"
        },
        {
          "header": "PERCENTAGE",
          "key": "percentage",
          "datatype": "percentage",
          "justification": "right"
        }
      ]
    }
    EOF
    
    cat > test_percentage_data.json << 'EOF'
    [
      {"name": "Item A", "percentage": "25%"},
      {"name": "Item B", "percentage": "50%"}
    ]
    EOF
    
    draw_table test_percentage_layout.json test_percentage_data.json
}
```

3. Run your tests:

```bash
# Add to the main script or test script
test_percentage_datatype
```

## Best Practices for Extensions

1. **Maintain Compatibility**: Ensure backward compatibility with existing features
2. **Follow Naming Conventions**: Use consistent naming patterns for functions and variables
3. **Add Documentation**: Document new features and update usage examples
4. **Error Handling**: Include proper validation and error messages
5. **Performance**: Consider the impact on performance, especially for large datasets
6. **Testing**: Create test cases to verify functionality

## Common Pitfalls

1. **Shell Limitations**: Remember that Bash has limited mathematical capabilities; use `awk` for complex math
2. **Quoting**: Be careful with variable quoting to handle spaces and special characters
3. **Escaping**: Properly escape characters in regular expressions and JSON
4. **Portability**: Test on different terminal types and shells if portability is important
5. **Error Propagation**: Ensure errors are properly reported up the call stack