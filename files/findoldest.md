# Find Oldest Files

A BASH script that finds the oldest files in a directory tree with detailed file information and optional date filtering.

## Usage

```bash
# Find oldest files in current directory
./findoldest.sh

# Find oldest files in specific directory
./findoldest.sh /path/to/directory

# Find files older than specific date
./findoldest.sh --before 20240115

# Find files older than date in specific directory
./findoldest.sh /path/to/directory --before 20240115
```

## Example Output

```
-rw-r--r--  1 user group    1234 2024-01-15 10:30:45.123 +0000 /path/to/oldfile.txt
```

## Features

- Recursively searches directories
- Shows detailed file information:
  - File permissions
  - Number of hard links
  - Owner and group
  - File size
  - Last modified timestamp
  - Full path
- Optional date filtering with --before flag
- Progress indicator with:
  - Percentage complete
  - Files per second
  - Estimated time remaining
- Handles multiple files with same timestamp
- Converts paths to absolute form

## Dependencies

- Standard BASH utilities: find, stat, date
- realpath command