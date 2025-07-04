#!/usr/bin/env bash
# Example of using tables.sh as a sourced library

# Source the tables library
source "$(dirname "$0")/tables.sh"

echo "=== Example 1: Using tables_render with files ==="
# This works the same as running tables.sh directly
if [[ -f "$(dirname "$0")/tst/layout_basic.json" && -f "$(dirname "$0")/tst/data_basic.json" ]]; then
    tables_render "$(dirname "$0")/tst/layout_basic.json" "$(dirname "$0")/tst/data_basic.json"
else
    echo "Test files not found, skipping file-based example"
fi

echo -e "\n=== Example 2: Using tables_render_from_json ==="
# This allows you to pass JSON directly as strings
layout_json='{
  "theme": "Blue",
  "title": "Dynamic Table from JSON",
  "title_position": "center",
  "columns": [
    {"header": "Name", "key": "name", "datatype": "text", "justification": "left"},
    {"header": "Age", "key": "age", "datatype": "int", "justification": "right", "summary": "avg"},
    {"header": "Score", "key": "score", "datatype": "num", "justification": "right", "summary": "sum"}
  ]
}'

data_json='[
  {"name": "Alice", "age": 30, "score": 95},
  {"name": "Bob", "age": 25, "score": 87},
  {"name": "Charlie", "age": 35, "score": 92},
  {"name": "Diana", "age": 28, "score": 98}
]'

tables_render_from_json "$layout_json" "$data_json"

echo -e "\n=== Example 3: Using utility functions ==="
echo "Available themes: $(tables_get_themes)"
echo "Tables version: $(tables_version)"

echo -e "\n=== Example 4: Multiple tables in sequence ==="
# When sourced, you can easily create multiple tables without launching separate processes

# First table - Red theme
layout1='{
  "theme": "Red",
  "title": "Sales Data Q1",
  "title_position": "left",
  "columns": [
    {"header": "Month", "key": "month", "datatype": "text"},
    {"header": "Revenue", "key": "revenue", "datatype": "num", "summary": "sum"}
  ]
}'

data1='[
  {"month": "January", "revenue": 15000},
  {"month": "February", "revenue": 18000},
  {"month": "March", "revenue": 22000}
]'

tables_render_from_json "$layout1" "$data1"

echo ""

# Second table - Blue theme
layout2='{
  "theme": "Blue",
  "title": "Sales Data Q2",
  "title_position": "right",
  "columns": [
    {"header": "Month", "key": "month", "datatype": "text"},
    {"header": "Revenue", "key": "revenue", "datatype": "num", "summary": "sum"}
  ]
}'

data2='[
  {"month": "April", "revenue": 25000},
  {"month": "May", "revenue": 28000},
  {"month": "June", "revenue": 31000}
]'

tables_render_from_json "$layout2" "$data2"

echo -e "\n=== Example 5: Using format_with_commas utility ==="
echo "Formatting large numbers:"
echo "1000000 -> $(format_with_commas 1000000)"
echo "1234567890 -> $(format_with_commas 1234567890)"

echo -e "\n=== Example 6: Resetting state between tables ==="
echo "You can reset all global state if needed:"
tables_reset
echo "State reset complete."

echo -e "\nAll examples completed!"
