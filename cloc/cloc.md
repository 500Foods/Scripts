# CLOC GitHub Action

This GitHub Action automatically counts lines of code in your repository and maintains this information in your README.md file. It provides a comprehensive breakdown of your codebase by language, including detailed statistics about code, comments, and blank lines.

## Features

- **Automatic Updates**: Runs on push/pull requests to main branch
- **Language Detection**: Automatic language detection with custom mapping support
- **Detailed Statistics**: Counts code, comments, and blank lines
- **README Integration**: Automatically updates README.md with latest statistics
- **Ignored Files Reporting**: Tracks skipped files with reasons
- **Custom Language Mapping**: Support for forcing specific file extensions to be counted as particular languages

## Setup

1. **Add the Workflow File**:
   Create `.github/workflows/cloc.yml`:
   ```yaml
   name: Count Lines of Code
   on:
     push:
       branches: [ main ]
     pull_request:
       branches: [ main ]

   jobs:
     cloc:
       runs-on: ubuntu-latest
       permissions:
         contents: write
       steps:
         - uses: actions/checkout@v4
         - uses: djdefi/cloc-action@main
         # ... additional steps as needed
   ```

2. **Prepare README.md**:
   Add these markers where you want the statistics to appear:
   ```markdown
   <!--CLOC-START -->
   Statistics will appear here
   <!--CLOC-END-->
   ```

## Configuration Options

### Basic Configuration

```yaml
- uses: djdefi/cloc-action@main
  with:
    options: --force-lang=Pascal,inc --report-file=cloc.txt --ignored=cloc-ignored.txt
```

### Available Options

1. **Language Mapping**:
   ```yaml
   --force-lang=Language,extension
   ```
   Example: `--force-lang=Pascal,inc` counts .inc files as Pascal

2. **Output Files**:
   - `--report-file=cloc.txt`: Main statistics file
   - `--ignored=cloc-ignored.txt`: List of ignored files

3. **Custom Filters**:
   ```yaml
   options: --exclude-dir=vendor,node_modules --exclude-ext=json,md
   ```

## Output Format

The action generates a formatted output like this:
```cloc
Last updated at 2025-05-26 19:34:20 UTC
-------------------------------------------------------------------------------
Language                     files          blank        comment           code
-------------------------------------------------------------------------------
JavaScript                      25           1234            856           5678
Python                         15            567            234           3456
CSS                            8            123             45           1234
-------------------------------------------------------------------------------
SUM:                          48           1924           1135          10368
-------------------------------------------------------------------------------
5 Files were skipped (duplicate, binary, or without source code):
  json: 2
  md: 1
  lock: 1
  git: 1
```

## Customization

### 1. Modifying Output Format

The workflow splits and reconstructs the README.md file:
```yaml
- run: csplit README.md /\<\!--CLOC/ {1}
- run: cp xx00 README.md
- run: echo "<!--CLOC-START -->" >> README.md
# ... additional formatting steps
```

### 2. Custom File Processing

```yaml
- run: |
    awk '{sub(/:.*/,""); ext=tolower($1); ext=substr(ext, match(ext, /[^\/]*$/)); ext=substr(ext, match(ext, /\.[^.]*$/)+1); counts[ext]++} END {for(i in counts) {printf("  %s: %d\n",i,counts[i])}}' cloc-ignored.txt | sort -t: -k2nr -k1 >> README.md
```
This script:
- Processes ignored files
- Groups by extension
- Sorts by count and name

## Best Practices

1. **Repository Setup**:
   - Add appropriate entries to .gitignore
   - Consider excluding test files or generated code
   - Document custom language mappings

2. **Workflow Configuration**:
   - Use specific action versions for stability
   - Configure appropriate permissions
   - Add meaningful commit messages

3. **Maintenance**:
   - Regularly update action versions
   - Review ignored files list
   - Monitor action execution time

## Troubleshooting

Common issues and solutions:

1. **Action Fails to Run**:
   - Check repository permissions
   - Verify README.md markers
   - Ensure workflow file is properly formatted

2. **Incorrect Counts**:
   - Review language mappings
   - Check excluded directories
   - Verify file extensions

3. **README Not Updating**:
   - Check commit permissions
   - Verify marker placement
   - Review workflow logs

## Advanced Usage

### 1. Custom Commit Configuration

```yaml
- uses: stefanzweifel/git-auto-commit-action@v5
  with:
    skip_dirty_check: true
    branch: main
    file_pattern: 'README.md'
    commit_message: "docs: update code statistics"
```

### 2. Scheduled Updates

```yaml
on:
  schedule:
    - cron: '0 0 * * 0'  # Weekly on Sunday
  push:
    branches: [ main ]
```

### 3. Custom Processing

Add additional steps for custom statistics:
```yaml
- name: Custom Statistics
  run: |
    echo "## Additional Statistics" >> README.md
    echo "Generated on: $(date)" >> README.md
```

## Security Considerations

1. **Permissions**:
   - Use minimal required permissions
   - Review auto-commit settings
   - Monitor workflow access

2. **Data Protection**:
   - Consider excluding sensitive files
   - Review ignored files list
   - Monitor output for sensitive information

3. **Action Security**:
   - Use pinned action versions
   - Review action updates
   - Monitor dependencies