# Week Number

A Python script that calculates and displays ISO week numbers along with formatted dates. It follows the ISO-8601 standard where weeks start on Monday and the first week of the year contains January 4th.

## Usage

```bash
# Get week number for current date
./weeknumber.py

# Get week number for specific date
./weeknumber.py 2024-01-15
```

## Example Output

```console
2024-01-15 (Mon) W02
```

## Features

- Calculates ISO week numbers
- Accepts optional date parameter in YYYY-MM-DD format
- Displays date with weekday abbreviation
- Uses Thursday-based week numbering (ISO-8601 standard)
- Handles date adjustments for correct week calculations

## Installation

1. Make the script executable:

   ```bash
   chmod +x weeknumber.py
   ```

2. Ensure the script is in your PATH:

   ```bash
   # Add to ~/.bashrc or ~/.zshrc
   export PATH="/path/to/scripts/dates:$PATH"
   ```

## Dependencies

- Python 3.x
- Standard library modules: sys, datetime
- No external dependencies required

## Notes

- This script is a dependency for uptime-fancy.sh
- Can be used standalone or as part of other scripts
- Follows ISO-8601 week numbering standard
- Handles date calculations automatically for correct week numbers
