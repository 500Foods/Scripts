# Uptime Fancy

A BASH script that combines the current week number with a nicely formatted system uptime display. It takes the standard Linux uptime output and condenses it into a more compact format.

## Usage

```bash
./uptime-fancy.sh
```

## Example Output

```console
2024-01-15 (Mon) W03 Up: 5d 2h 30m
```

## Features

- Displays current date with ISO week number
- Shows system uptime in a condensed format (e.g., "5d 2h 30m" instead of "5 days 2 hours 30 minutes")
- Combines week number from weeknumber.py with formatted uptime

## Installation

1. Make the script executable:

   ```bash
   chmod +x uptime-fancy.sh
   ```

2. Ensure the script is in your PATH:

   ```bash
   # Add to ~/.bashrc or ~/.zshrc
   export PATH="/path/to/scripts/dates:$PATH"
   ```

3. Ensure weeknumber.py is also in your PATH as this script depends on it

## Dependencies

- BASH shell environment
- weeknumber.py (must be in PATH)
- Standard Linux uptime command

## Notes

- This script depends on weeknumber.py being accessible in your PATH
- Both scripts should ideally be in the same directory
- The script formats uptime output to be more compact (e.g., "5d" instead of "5 days")
