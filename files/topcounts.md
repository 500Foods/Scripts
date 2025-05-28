# Top File Counts

A Python script that finds directories containing the most files in a directory tree.

## Usage

```bash
./topcounts.py <num_dirs> <start_dir>

# Example: Show top 10 directories with most files starting from current directory
./topcounts.py 10 .
```

## Example Output

```
Index  Counts  Directory
    1     523  /path/to/dir1
    2     342  /path/to/dir2
    3     156  /path/to/dir3
```

## Features

- Recursively counts files in directories
- Configurable number of results to display
- Formatted table output with:
  - Index number
  - File count
  - Full directory path
- Sorts results by file count in descending order
- Handles file access errors gracefully

## Dependencies

- Python 3
- Standard library modules: os, sys