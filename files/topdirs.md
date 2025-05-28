# Top Directories by Size

A Python script that finds the largest directories (by total size) in a directory tree.

## Usage

```bash
./topdirs.py <num_dirs> <start_dir>

# Example: Show 10 largest directories starting from current directory
./topdirs.py 10 .
```

## Example Output

```console
Index  Size (MB)  Directory
    1    1024.5  /path/to/dir1
    2     756.2  /path/to/dir2
    3     512.8  /path/to/dir3
```

## Features

- Recursively calculates total size of directories
- Configurable number of results to display
- Formatted table output with:
  - Index number
  - Directory size in megabytes (MB)
  - Full directory path
- Sorts results by size in descending order
- Handles file access errors gracefully
- Accurate size calculations using os.path.getsize()

## Dependencies

- Python 3
- Standard library modules: os, sys
