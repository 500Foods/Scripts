# Tables.sh - Sourced Library Usage

The `tables.sh` script can now be used both as a standalone command-line tool and as a sourced library in other bash scripts. This provides significant performance benefits when generating multiple tables, as you avoid the overhead of launching separate processes.

## Quick Start

```bash
# Source the library
source tables.sh

# Use the functions
tables_render_from_json "$layout_json" "$data_json"
```

## Available Functions

When sourced, the following functions are exported and available:

### Core Functions

#### `tables_render <layout_file> <data_file> [options]`
Renders a table from JSON files (same as command-line usage).

```bash
tables_render layout.json data.json --debug
```

#### `tables_render_from_json <layout_json> <data_json> [options]`
Renders a table directly from JSON strings without requiring files.

```bash
layout='{"columns":[{"header":"Name","key":"name"}]}'
data='[{"name":"Alice"},{"name":"Bob"}]'
tables_render_from_json "$layout" "$data"
```

#### `draw_table <layout_file> <data_file> [options]`
The core table rendering function (same as `tables_render`).

### Utility Functions

#### `tables_get_themes`
Returns available themes.

```bash
echo "$(tables_get_themes)"
# Output: Available themes: Red, Blue
```

#### `tables_version`
Returns the library version.

```bash
echo "Version: $(tables_version)"
# Output: Version: 1.0.2
```

#### `tables_reset`
Resets all global state variables. Useful when generating multiple tables to ensure clean state.

```bash
tables_reset
```

#### `get_theme <theme_name>`
Sets the current theme (Red, Blue).

```bash
get_theme "Blue"
```

#### `format_with_commas <number>`
Formats numbers with comma separators.

```bash
formatted=$(format_with_commas 1234567)
echo "$formatted"  # Output: 1,234,567
```

#### `get_display_length <text>`
Gets the display length of text (excluding ANSI escape sequences).

```bash
length=$(get_display_length "Hello World")
echo "$length"  # Output: 11
```

## Benefits of Sourcing

### Performance
- **No process overhead**: Functions run in the current shell
- **Faster execution**: No script startup time for multiple tables
- **Memory efficiency**: Shared state and functions

### Integration
- **Direct JSON handling**: Pass JSON strings without temporary files
- **State management**: Control global state between table generations
- **Utility access**: Use formatting and helper functions directly

## Usage Patterns

### Single Table from JSON Strings

```bash
#!/usr/bin/env bash
source tables.sh

layout='{
  "theme": "Blue",
  "title": "User Report",
  "columns": [
    {"header": "Name", "key": "name", "datatype": "text"},
    {"header": "Score", "key": "score", "datatype": "num", "summary": "sum"}
  ]
}'

data='[
  {"name": "Alice", "score": 95},
  {"name": "Bob", "score": 87}
]'

tables_render_from_json "$layout" "$data"
```

### Multiple Tables in Sequence

```bash
#!/usr/bin/env bash
source tables.sh

# Generate multiple reports
for quarter in Q1 Q2 Q3 Q4; do
    layout="{\"title\":\"Sales $quarter\",\"columns\":[...]}"
    data="[...]"  # Load quarter-specific data
    
    tables_render_from_json "$layout" "$data"
    echo ""  # Add spacing between tables
    
    # Reset state between tables if needed
    tables_reset
done
```

### Dynamic Table Generation

```bash
#!/usr/bin/env bash
source tables.sh

generate_report() {
    local title="$1"
    local theme="$2"
    shift 2
    local data_items=("$@")
    
    # Build JSON dynamically
    local layout="{\"theme\":\"$theme\",\"title\":\"$title\",\"columns\":[...]}"
    local data="["
    for item in "${data_items[@]}"; do
        data+="{\"item\":\"$item\"},"
    done
    data="${data%,}]"
    
    tables_render_from_json "$layout" "$data"
}

generate_report "Inventory" "Red" "Apples" "Bananas" "Oranges"
```

### Using Utility Functions

```bash
#!/usr/bin/env bash
source tables.sh

# Format numbers for display
sales_total=1234567
formatted_total=$(format_with_commas "$sales_total")
echo "Total Sales: $formatted_total"

# Check available themes
echo "$(tables_get_themes)"

# Get version info
echo "Using tables.sh version $(tables_version)"
```

## Backward Compatibility

The script maintains full backward compatibility:

```bash
# Still works as command-line tool
./tables.sh layout.json data.json

# Also works when sourced
source tables.sh
tables_render layout.json data.json
```

## State Management

When sourced, the library uses global variables. Use `tables_reset` to clean state between table generations:

```bash
source tables.sh

# Generate first table
tables_render_from_json "$layout1" "$data1"

# Reset state before next table
tables_reset

# Generate second table
tables_render_from_json "$layout2" "$data2"
```

## Error Handling

Functions return appropriate exit codes:

```bash
source tables.sh

if tables_render_from_json "$layout" "$data"; then
    echo "Table generated successfully"
else
    echo "Error generating table" >&2
    exit 1
fi
```

## Example Script

See `example_sourced.sh` for a comprehensive demonstration of all sourced functionality.

```bash
./example_sourced.sh
```

## Performance Comparison

**Command-line approach** (separate processes):
```bash
for i in {1..10}; do
    ./tables.sh layout.json data.json
done
```

**Sourced approach** (single process):
```bash
source tables.sh
for i in {1..10}; do
    tables_render layout.json data.json
done
```

The sourced approach is significantly faster for multiple table generations due to eliminated process startup overhead.
