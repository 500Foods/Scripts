# Top Files by Size

A Python script that finds the largest files (above 1MB) in a directory tree.

## Usage

```bash
./topfiles.py <num_files> <start_dir>

# Example: Show 10 largest files starting from current directory
./topfiles.py 10 .
```

## Example Output

```
Index  Size (MB)  Filename
    1    256.4  /path/to/large1.iso
    2    128.7  /path/to/large2.zip
    3     64.2  /path/to/large3.tar
```

## Features

- Recursively searches for large files
- Minimum file size threshold of 1MB
- Configurable number of results to display
- Formatted table output with:
  - Index number
  - File size in megabytes (MB)
  - Full file path
- Sorts results by size in descending order
- Handles file access errors gracefully
- Memory efficient processing of large directory trees

## Dependencies

- Python 3
- Standard library modules: os, sys