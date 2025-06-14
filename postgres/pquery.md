# pquery.sh - PostgreSQL Query Table Renderer

## Overview
`pquery.sh` is a Bash script designed to execute PostgreSQL SELECT queries and render the results as formatted terminal tables. This tool is ideal for integrating PostgreSQL data with terminal-based workflows, providing visually appealing table output with metadata-driven formatting.

## Purpose
- Execute any SELECT query and render results as a formatted terminal table.
- Automatically map PostgreSQL data types to appropriate display formats and justifications.
- Support customization of table appearance with themes and titles.

## Usage
```bash
./pquery.sh [-d|--debug] [-n|--name "Table Name"] [-m|--theme Red|Blue] [-q|--quiet] [-h|--help] ["<query>"]
```
or
```bash
cat query.sql | ./pquery.sh [-d|--debug] [-n|--name "Table Name"] [-m|--theme Red|Blue] [-q|--quiet] [-h|--help]
```

### Options
- `-d`, `--debug`: Enable debug mode, outputting detailed logs and preserving temporary files for troubleshooting.
- `-n`, `--name <name>`: Set a custom table header name (default: "Query Results").
- `-m`, `--theme <Red|Blue>`: Choose the table theme, either 'Red' or 'Blue' (default: Red).
- `-q`, `--quiet`: Suppress version information output.
- `-h`, `--help`: Display usage information and options.

### Input Methods
- **Command Line**: Provide the query directly as an argument (e.g., `./pquery.sh "SELECT * FROM table"`).
- **Piped Input**: Pipe a query from a file or another command (e.g., `cat query.sql | ./pquery.sh`).

## Example
```bash
./pquery.sh -n "My Fancy Query" "SELECT lookup_id, key_idx FROM app.lookups WHERE lookup_id=38"
```
or
```bash
cat test.sql | ./pquery.sh -n "My Fancy Query" -m Blue
```

**Output (non-debug mode):**
- A formatted terminal table displaying query results with column headers, aligned data based on data type (numeric right-aligned, text left-aligned), and a footer summarizing rows and columns.

**Output (debug mode):**
- Full query results in JSON format.
- Metadata in JSON format (column names and data types).
- Debug log saved at `/tmp/pquery_debug.log`.

## Requirements
- PostgreSQL 11 or higher (for `\gdesc` command support).
- `jq` for JSON parsing.
- `tables/tables.sh` for rendering terminal tables.

## Version
- **1.0.7** (Updated on 2025-06-13)

## Change History
- **1.0.7 (2025-06-13)**: Removed `--table` option as table output is the sole purpose, added support for piped query input (e.g., `cat query.sql | pquery.sh`).
- **1.0.6 (2025-06-13)**: Added `--help` option, one-character shorthand options (`-d`, `-t`, `-n`, `-m`, `-q`, `-h`), added `--quiet` mode to suppress version info output.
- **1.0.5 (2025-06-13)**: Made parameters non-positional, set `--table` as default, added `--name` for custom table header, added default footer with row/column summary, set footer right-aligned, added `--theme` parameter, removed erroneous error message after successful table rendering.
- **1.0.4 (2025-06-13)**: Refactored script with modular functions, added `--table` option to render results as ASCII tables using `tables/tables.sh`, updated version.
- **1.0.3 (2025-06-13)**: Updated version number, enhanced comments for developer clarity, added detailed explanations for key functionalities.
- **1.0.2 (2025-06-13)**: Fixed metadata parsing by clipping top lines and filtering separator, added change history, updated version display.
- **1.0.1 (2025-06-13)**: Added descriptive header, APPVERSION, `--debug` option, query summary (execution time, rows, columns), non-debug output format.
- **1.0.0 (2025-06-12)**: Initial version with JSON results, `\gdesc` metadata, `~/.pgpass` support.

## Author
- Collaborative effort with user input and AI assistance.

## Notes
- Uses `~/.pgpass` for database connection details in the format `host:port:database:user:password`.
- Ensure `~/.pgpass` has correct permissions (0600) for security.
