#!/bin/bash

# pquery.sh: Execute a PostgreSQL SELECT query and output results and metadata as JSON
# Purpose: Run any SELECT query, return results as a JSON array, and provide column metadata
#          (names and data types) without executing the query for metadata.
# Usage: ./pquery.sh [--debug] "<query>"
# Example: ./pquery.sh "SELECT lookup_id, key_idx FROM app.lookups WHERE lookup_id=38 AND key_idx=1"
# Output (non-debug):
#   - Query executed in <time>s
#   - Rows returned: <count>
#   - Columns returned: <count>
#   - Metadata: [JSON array]
# Output (debug): Query results JSON, metadata JSON, and debug log at /tmp/pquery_debug.log
# Requirements: PostgreSQL 11+ (for \gdesc), jq for JSON parsing
# Version: 1.0.2
# Author: Collaborative effort with user input and AI assistance
# Notes: Uses ~/.pgpass for connection details (format: host:port:database:user:password)
#
# Change History:
#   1.0.2 (2025-06-13): Fixed metadata parsing by clipping top lines and filtering separator,
#                       added change history, updated version display.
#   1.0.1 (2025-06-13): Added descriptive header, APPVERSION, --debug option, query summary
#                       (execution time, rows, columns), non-debug output format.
#   1.0.0 (2025-06-12): Initial version with JSON results, \gdesc metadata, ~/.pgpass support.

APPNAME="pquery"
APPVERSION="1.0.2"

# Exit on error
set -e

# Parse --debug option
DEBUG=false
if [ "$1" = "--debug" ]; then
  DEBUG=true
  shift
  set -x
fi

# Initialize debug log
DEBUG_LOG=/tmp/pquery_debug.log
if [ "$DEBUG" = true ]; then
  : > "$DEBUG_LOG"
  echo "DEBUG: Starting $APPNAME v$APPVERSION" >> "$DEBUG_LOG"
else
  DEBUG_LOG=/dev/null
fi

# Output app name and version
echo "$APPNAME v$APPVERSION"

# Validate query
if [ -z "$1" ]; then
  echo "Error: Usage: $0 [--debug] <query>" >&2
  exit 1
fi
QUERY="$1"
echo "DEBUG: Query: $QUERY" >> "$DEBUG_LOG"

# Parse ~/.pgpass
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

# Function to run psql for queries
run_psql_query() {
  echo "DEBUG: Running psql with args: $@" >> "$DEBUG_LOG"
  psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" --tuples-only --no-align "$@"
}

# Function to run psql for metadata (\gdesc)
run_psql_metadata() {
  echo "DEBUG: Running psql for metadata with args: $@" >> "$DEBUG_LOG"
  psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" "$@"
}

# Test connection
echo "DEBUG: Testing connection" >> "$DEBUG_LOG"
if ! run_psql_query -c "SELECT 1;" >/dev/null; then
  echo "Error: Failed to connect to database" >&2
  exit 1
fi
echo "DEBUG: Connection successful" >> "$DEBUG_LOG"

# Run query and get JSON results
echo "DEBUG: Running main query" >> "$DEBUG_LOG"
TEMP_JSON=$(mktemp)
TEMP_ERR=$(mktemp)
echo "DEBUG: TEMP_JSON=$TEMP_JSON, TEMP_ERR=$TEMP_ERR" >> "$DEBUG_LOG"
# Measure query execution time
START_TIME=$(date +%s.%N)
if ! run_psql_query -c "SET search_path TO app, public; SELECT json_agg(row_to_json(t)) FROM ($QUERY) t;" 2> "$TEMP_ERR" > "$TEMP_JSON"; then
  echo "Error: Failed to execute query: $QUERY" >&2
  cat "$TEMP_ERR" >&2
  exit 1
fi
END_TIME=$(date +%s.%N)
EXEC_TIME=$(echo "$END_TIME - $START_TIME" | bc)
echo "DEBUG: Query executed in ${EXEC_TIME}s" >> "$DEBUG_LOG"
# Filter out SET and empty lines, default to []
RESULTS=$(grep -v '^SET$' "$TEMP_JSON" | grep -v '^$' || echo "[]")
echo "DEBUG: Query results: $RESULTS" >> "$DEBUG_LOG"

# Count rows
ROW_COUNT=$(echo "$RESULTS" | jq 'if type == "array" then length else 0 end')
echo "DEBUG: Rows returned: $ROW_COUNT" >> "$DEBUG_LOG"

# Get metadata with \gdesc
echo "DEBUG: Running metadata query" >> "$DEBUG_LOG"
TEMP_METADATA=$(mktemp)
echo "DEBUG: TEMP_METADATA=$TEMP_METADATA" >> "$DEBUG_LOG"
# Pipe query with \gdesc
if ! echo "SET search_path TO app, public; $QUERY \gdesc" | run_psql_metadata 2> "$TEMP_ERR" > "$TEMP_METADATA"; then
  echo "Error: Failed to retrieve metadata for query: $QUERY" >&2
  cat "$TEMP_ERR" >&2
  exit 1
fi
echo "DEBUG: Raw contents of $TEMP_METADATA:" >> "$DEBUG_LOG"
cat "$TEMP_METADATA" >> "$DEBUG_LOG"
# Skip top line (SET), filter header, separator, footer, and empty lines
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

# Count columns
COLUMN_COUNT=$(echo "$METADATA" | jq 'length')
echo "DEBUG: Columns returned: $COLUMN_COUNT" >> "$DEBUG_LOG"

# Output (non-debug mode)
if [ "$DEBUG" = false ]; then
  echo "- Query executed in ${EXEC_TIME}s"
  echo "- Rows returned: $ROW_COUNT"
  echo "- Columns returned: $COLUMN_COUNT"
  echo "- Metadata:"
  echo "$METADATA"
else
  # Output (debug mode)
  echo "$RESULTS"
  echo "$METADATA"
fi
echo "DEBUG: Output complete" >> "$DEBUG_LOG"

# Preserve temporary files in debug mode
if [ "$DEBUG" = true ]; then
  echo "DEBUG: Temporary files preserved: $TEMP_JSON, $TEMP_METADATA, $TEMP_ERR" >> "$DEBUG_LOG"
else
  rm -f "$TEMP_JSON" "$TEMP_METADATA" "$TEMP_ERR"
fi
exit 0
