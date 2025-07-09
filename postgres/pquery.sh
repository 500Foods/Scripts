#!/bin/bash

# pquery.sh: Execute a PostgreSQL SELECT query and output results as a formatted table
# Purpose: Run any SELECT query and render results as an ASCII table with metadata support.
# Usage: ./pquery.sh [-d|--debug] [-n|--name "Table Name"] [-m|--theme Red|Blue] [-q|--quiet] [-h|--help] ["<query>"]
#        or: cat query.sql | ./pquery.sh [-d|--debug] [-n|--name "Table Name"] [-m|--theme Red|Blue] [-q|--quiet] [-h|--help]
# Example: ./pquery.sh -n "My Fancy Query" "SELECT lookup_id, key_idx FROM app.lookups WHERE lookup_id=38"
#          or: cat test.sql | ./pquery.sh -n "My Fancy Query" -m Blue
# Output (non-debug): Formatted ASCII table using tables/tables.sh with customizable name and theme
# Output (debug): Query results JSON, metadata JSON, and debug log at /tmp/pquery_debug.log
# Requirements: PostgreSQL 11+ (for \gdesc), jq for JSON parsing, tables/tables.sh for table output
# Version: 1.0.7
# Author: Collaborative effort with user input and AI assistance
# Notes: Uses ~/.pgpass for connection details (format: host:port:database:user:password)
#
# Change History:
#   1.0.7 (2025-06-13): Removed --table option as table output is the sole purpose, added support for piped query input (e.g., cat query.sql | pquery.sh).
#   1.0.6 (2025-06-13): Added --help option, one-character shorthand options (-d, -t, -n, -m, -q, -h),
#                       added --quiet mode to suppress version info output.
#   1.0.5 (2025-06-13): Made parameters non-positional, set --table as default, added --name for custom table header,
#                       added default footer with row/column summary, set footer right-aligned, added --theme parameter,
#                       removed erroneous error message after successful table rendering.
#   1.0.4 (2025-06-13): Refactored script with modular functions, added --table option to render
#                       results as ASCII tables using tables/tables.sh, updated version.
#   1.0.3 (2025-06-13): Updated version number, enhanced comments for developer clarity,
#                       added detailed explanations for key functionalities.
#   1.0.2 (2025-06-13): Fixed metadata parsing by clipping top lines and filtering separator,
#                       added change history, updated version display.
#   1.0.1 (2025-06-13): Added descriptive header, APPVERSION, --debug option, query summary
#                       (execution time, rows, columns), non-debug output format.
#   1.0.0 (2025-06-12): Initial version with JSON results, \gdesc metadata, ~/.pgpass support.

APPNAME="pquery"
APPVERSION="1.0.7"

# Exit on error
set -e

# Parse command line options
DEBUG=false
TABLE_NAME="Query Results"
THEME="Red"
QUERY=""
QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--debug)
      DEBUG=true
      shift
      ;;
    -n|--name)
      if [[ $# -gt 1 ]]; then
        TABLE_NAME="$2"
        shift 2
      else
        echo "Error: --name requires a value" >&2
        exit 1
      fi
      ;;
    -m|--theme)
      if [[ $# -gt 1 && ("$2" == "Red" || "$2" == "Blue") ]]; then
        THEME="$2"
        shift 2
      else
        echo "Error: --theme requires a value of 'Red' or 'Blue'" >&2
        exit 1
      fi
      ;;
    -q|--quiet)
      QUIET=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [-d|--debug] [-n|--name \"Table Name\"] [-m|--theme Red|Blue] [-q|--quiet] [-h|--help] [\"<query>\"]"
      echo "       or: cat query.sql | $0 [-d|--debug] [-n|--name \"Table Name\"] [-m|--theme Red|Blue] [-q|--quiet] [-h|--help]"
      echo "Example: $0 -n \"My Fancy Query\" \"SELECT lookup_id, key_idx FROM app.lookups WHERE lookup_id=38\""
      echo "         or: cat test.sql | $0 -n \"My Fancy Query\" -m Blue"
      echo "Options:"
      echo "  -d, --debug    Enable debug mode with detailed logs"
      echo "  -n, --name     Set custom table header name (default: Query Results)"
      echo "  -m, --theme    Set table theme to 'Red' or 'Blue' (default: Red)"
      echo "  -q, --quiet    Suppress version information output"
      echo "  -h, --help     Display this help message"
      exit 0
      ;;
    *)
      QUERY="$1"
      shift
      ;;
  esac
done

# Initialize debug log
DEBUG_LOG=/tmp/pquery_debug.log
if [ "$DEBUG" = true ]; then
  : > "$DEBUG_LOG"
  echo "DEBUG: Starting $APPNAME v$APPVERSION" >> "$DEBUG_LOG"
else
  DEBUG_LOG=/dev/null
fi

# Output app name and version unless in quiet mode
if [ "$QUIET" = false ]; then
  echo "$APPNAME v$APPVERSION"
fi

# Check if query is provided via command line or piped input
if [ -z "$QUERY" ]; then
  # Check if input is piped
  if ! read -t 0; then
    echo "Error: Usage: $0 [-d|--debug] [-n|--name \"Table Name\"] [-m|--theme Red|Blue] [-q|--quiet] [-h|--help] [\"<query>\"]" >&2
    echo "       or: cat query.sql | $0 [-d|--debug] [-n|--name \"Table Name\"] [-m|--theme Red|Blue] [-q|--quiet] [-h|--help]" >&2
    exit 1
  else
    # Read piped input
    QUERY=$(cat)
    if [ -z "$QUERY" ]; then
      echo "Error: No query provided via pipe or command line" >&2
      exit 1
    fi
  fi
fi
echo "DEBUG: Query: $QUERY" >> "$DEBUG_LOG"

# Function to parse ~/.pgpass for database connection details
# This function reads the PostgreSQL password file (~/.pgpass) to extract connection parameters
# without hardcoding sensitive information in the script. It ensures secure handling of credentials
# by masking the password in debug logs and validating the file's permissions for security.
parse_pgpass() {
  PGPASS_FILE="$HOME/.pgpass"
  echo "DEBUG: Checking $PGPASS_FILE" >> "$DEBUG_LOG"
  if [ ! -f "$PGPASS_FILE" ]; then
    echo "Error: $PGPASS_FILE not found" >&2
    exit 1
  fi
  if [ "$(stat -c %a "$PGPASS_FILE" 2>/dev/null || stat -f %A "$PGPASS_FILE")" != "600" ]; then
    echo "Warning: $PGPASS_FILE should have 0600 permissions (run: chmod 0600 $PGPASS_FILE)" >&2
  fi
  read -r PGPASS_LINE < <(grep -v '^#' "$PGPASS_FILE" | grep -v '^[[:space:]]*$' | head -n 1)
  if [ -z "$PGPASS_LINE" ]; then
    echo "Error: No valid entries in $PGPASS_FILE" >&2
    exit 1
  fi
  PGPASS_LOG=$(echo "$PGPASS_LINE" | sed 's/:[^:]*$/:********/')
  echo "DEBUG: pgpass line (masked): $PGPASS_LOG" >> "$DEBUG_LOG"
  IFS=':' read -r PGHOST PGPORT PGDATABASE PGUSER _ <<< "$PGPASS_LINE"
  if [ -z "$PGHOST" ] || [ -z "$PGPORT" ] || [ -z "$PGDATABASE" ] || [ -z "$PGUSER" ]; then
    echo "Error: Invalid ~/.pgpass entry: $PGPASS_LINE" >&2
    exit 1
  fi
  echo "DEBUG: Parsed: host=$PGHOST, port=$PGPORT, db=$PGDATABASE, user=$PGUSER" >> "$DEBUG_LOG"
}

# Function to run psql for queries
# This function executes the actual SQL query with specific formatting options to ensure
# the output is clean and suitable for JSON conversion. It uses '--tuples-only' to omit headers
# and '--no-align' to prevent extra spacing, making parsing easier.
run_psql_query() {
  echo "DEBUG: Running psql with args: $@" >> "$DEBUG_LOG"
  psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" --tuples-only --no-align "$@"
}

# Function to run psql for metadata (\gdesc)
# This function is specifically for retrieving metadata about the query using PostgreSQL's \gdesc
# command, which describes the structure of the result set (column names and types) without
# executing the query itself, thus saving on performance.
run_psql_metadata() {
  echo "DEBUG: Running psql for metadata with args: $@" >> "$DEBUG_LOG"
  psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" "$@"
}

# Function to test database connection
test_connection() {
  echo "DEBUG: Testing connection" >> "$DEBUG_LOG"
  if ! run_psql_query -c "SELECT 1;" >/dev/null; then
    echo "Error: Failed to connect to database" >&2
    exit 1
  fi
  echo "DEBUG: Connection successful" >> "$DEBUG_LOG"
}

# Function to execute the main query and get JSON results
# This section transforms the query results into JSON format using PostgreSQL's built-in
# functions. 'json_agg' aggregates rows into a JSON array, and 'row_to_json' converts each row
# into a JSON object. The 'search_path' is set to prioritize 'app' and 'public' schemas.
execute_query() {
  echo "DEBUG: Running main query" >> "$DEBUG_LOG"
  TEMP_JSON=$(mktemp)
  TEMP_ERR=$(mktemp)
  echo "DEBUG: TEMP_JSON=$TEMP_JSON, TEMP_ERR=$TEMP_ERR" >> "$DEBUG_LOG"
  # Measure query execution time to provide performance feedback to the user.
  START_TIME=$(date +%s.%N)
  if ! run_psql_query -c "SET search_path TO app, public; SELECT json_agg(row_to_json(t)) FROM ($QUERY) t;" 2> "$TEMP_ERR" > "$TEMP_JSON"; then
    echo "Error: Failed to execute query: $QUERY" >&2
    cat "$TEMP_ERR" >&2
    exit 1
  fi
  END_TIME=$(date +%s.%N)
  EXEC_TIME=$(echo "$END_TIME - $START_TIME" | bc)
  echo "DEBUG: Query executed in ${EXEC_TIME}s" >> "$DEBUG_LOG"
  # Filter out SET command output and empty lines from results, default to empty JSON array if no results.
  RESULTS=$(grep -v '^SET$' "$TEMP_JSON" | grep -v '^$' || echo "[]")
  echo "DEBUG: Query results: $RESULTS" >> "$DEBUG_LOG"
}

# Function to count rows in the results
count_rows() {
  ROW_COUNT=$(echo "$RESULTS" | jq 'if type == "array" then length else 0 end')
  echo "DEBUG: Rows returned: $ROW_COUNT" >> "$DEBUG_LOG"
}

# Function to get metadata with \gdesc
# Using PostgreSQL's \gdesc command to retrieve metadata about the query result structure
# without executing the full query. This is an efficient way to get column names and data types,
# which is particularly useful for applications that need to understand the schema of the result set.
get_metadata() {
  echo "DEBUG: Running metadata query" >> "$DEBUG_LOG"
  TEMP_METADATA=$(mktemp)
  echo "DEBUG: TEMP_METADATA=$TEMP_METADATA" >> "$DEBUG_LOG"
  # Pipe query with \gdesc to describe the result set structure.
  if ! echo "SET search_path TO app, public; $QUERY \gdesc" | run_psql_metadata 2> "$TEMP_ERR" > "$TEMP_METADATA"; then
    echo "Error: Failed to retrieve metadata for query: $QUERY" >&2
    cat "$TEMP_ERR" >&2
    exit 1
  fi
  echo "DEBUG: Raw contents of $TEMP_METADATA:" >> "$DEBUG_LOG"
  cat "$TEMP_METADATA" >> "$DEBUG_LOG"
  # Process metadata output: skip irrelevant lines (SET command, headers, separators, footers),
  # and parse the remaining lines into a JSON array of column metadata.
  METADATA=$(tail -n +4 "$TEMP_METADATA" | grep -v '^[[:space:]]*Column[[:space:]]*|' | grep -v '^[[:space:]]*-.*\+.*-[[:space:]]*|' | grep -v '^[[:space:]]*([0-9]\+ rows)' | grep -v '^$' | while IFS='|' read -r col_name data_type; do
    col_name=$(echo "$col_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    data_type=$(echo "$data_type" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    echo "{\"column_name\":\"$col_name\",\"data_type\":\"$data_type\"}"
  done | jq -s '.' || {
    echo "Error: Failed to parse metadata output" >&2
    cat "$TEMP_METADATA" >&2
    exit 1
  })
  echo "DEBUG: Filtered metadata lines:" >> "$DEBUG_LOG"
  tail -n +2 "$TEMP_METADATA" | grep -v '^[[:space:]]*Column[[:space:]]*|' | grep -v '^[[:space:]]*-.*\+.*-[[:space:]]*|' | grep -v '^[[:space:]]*([0-9]\+ rows)' | grep -v '^$' >> "$DEBUG_LOG"
  echo "DEBUG: Metadata: $METADATA" >> "$DEBUG_LOG"
}

# Function to count columns in the metadata
count_columns() {
  COLUMN_COUNT=$(echo "$METADATA" | jq 'length')
  echo "DEBUG: Columns returned: $COLUMN_COUNT" >> "$DEBUG_LOG"
}

# Function to render output in non-debug mode
render_output() {
  if [ "$DEBUG" = false ]; then
    render_table_output
  else
    # Output (debug mode)
    echo "$RESULTS"
    echo "$METADATA"
  fi
  echo "DEBUG: Output complete" >> "$DEBUG_LOG"
}

# Function to render output as a formatted table using tables/tables.sh
render_table_output() {
  # Save results and metadata to temporary files for table rendering
  RESULTS_FILE=$(mktemp)
  LAYOUT_FILE=$(mktemp)
  echo "$RESULTS" > "$RESULTS_FILE"
  
  # Create a layout JSON for tables.sh based on metadata with datatype mapping
  {
    echo "{"
    echo "  \"theme\": \"$THEME\","
    echo "  \"title\": \"$TABLE_NAME\","
    echo "  \"title_position\": \"left\","
    echo "  \"footer\": \"Rows: $ROW_COUNT, Columns: $COLUMN_COUNT\","
    echo "  \"footer_position\": \"right\","
    echo "  \"columns\": ["
    # Use a loop to process each metadata entry to avoid complex jq syntax issues
    FIRST=true
    while IFS=',' read -r col_name data_type; do
      col_name=$(echo "$col_name" | sed 's/^[[:space:]]*"\(.*\)"[[:space:]]*$/\1/')
      data_type=$(echo "$data_type" | sed 's/^[[:space:]]*"\(.*\)"[[:space:]]*$/\1/')
      key=$(echo "$col_name" | sed 's/ /_/g')
      if [[ "$data_type" =~ integer|bigint|smallint ]]; then
        datatype="int"
        justification="right"
      elif [[ "$data_type" =~ numeric|decimal|real|"double precision" ]]; then
        datatype="float"
        justification="right"
      elif [[ "$data_type" =~ character|varchar|text|date|timestamp|time|boolean ]]; then
        datatype="text"
        justification="left"
      else
        datatype="text"
        justification="left"
      fi
      if [ "$FIRST" = false ]; then
        echo ","
      fi
      echo "    { \"header\": \"$col_name\", \"key\": \"$key\", \"datatype\": \"$datatype\", \"justification\": \"$justification\" }"
      FIRST=false
    done < <(echo "$METADATA" | jq -r '.[] | [.column_name, .data_type] | @csv')
    echo "  ]"
    echo "}"
  } > "$LAYOUT_FILE"
  
  echo "DEBUG: Results saved to $RESULTS_FILE" >> "$DEBUG_LOG"
  echo "DEBUG: Layout saved to $LAYOUT_FILE" >> "$DEBUG_LOG"
  
  # Call tables.sh to render the table
  "../tables.c/tables" "$LAYOUT_FILE" "$RESULTS_FILE"
  
  # Clean up temporary files for table rendering
  if [ "$DEBUG" = false ]; then
    rm -f "$RESULTS_FILE" "$LAYOUT_FILE"
  else
    echo "DEBUG: Table rendering files preserved: $RESULTS_FILE, $LAYOUT_FILE" >> "$DEBUG_LOG"
  fi
}

# Function to clean up temporary files
cleanup() {
  if [ "$DEBUG" = true ]; then
    echo "DEBUG: Temporary files preserved: $TEMP_JSON, $TEMP_METADATA, $TEMP_ERR" >> "$DEBUG_LOG"
  else
    rm -f "$TEMP_JSON" "$TEMP_METADATA" "$TEMP_ERR"
  fi
}

# Main execution flow
parse_pgpass
test_connection
execute_query
count_rows
get_metadata
count_columns
render_output
cleanup

exit 0
