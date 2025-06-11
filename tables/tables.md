# Tables

A flexible utility for rendering JSON data as ASCII tables in terminal output. Tables.sh provides a powerful way to visualize structured data with customizable formatting, data processing, and display options.

## Overview

Tables.sh converts JSON data into beautifully formatted ASCII tables with the following features:

- Multiple visual themes with colored borders
- Support for various data types (text, numbers, Kubernetes CPU/memory values)
- Customizable column configurations (headers, alignment, formatting)
- Data processing capabilities (sorting, validation, totals calculation)
- Text wrapping and custom display options for null/zero values

## Usage

```bash
./tables.sh <layout_json_file> <data_json_file> [--debug] [--version]
```

### Parameters

- `layout_json_file`: JSON file defining table structure and formatting
- `data_json_file`: JSON file containing the data to display
- `--debug`: (Optional) Enable debug output
- `--version`: (Optional) Display version information

## Layout JSON Structure

The layout file defines how the table should be structured and formatted:

```json
{
  "theme": "Red",
  "sort": [
    {"key": "column_key", "direction": "asc", "priority": 1}
  ],
  "columns": [
    {
      "header": "COLUMN NAME",
      "key": "json_field_name",
      "justification": "left",
      "datatype": "text",
      "null_value": "blank",
      "zero_value": "blank",
      "total": "none",
      "break": false,
      "string_limit": 0,
      "wrap_mode": "clip",
      "wrap_char": "",
      "padding": 1
    }
  ]
}
```

### Theme Options

The `theme` field defines the visual appearance of the table:

- `"Red"`: Red borders and headers (default)
- `"Blue"`: Blue borders and headers

### Sort Configuration

The `sort` array allows sorting data by one or more columns:

- `key`: The column key to sort by
- `direction`: Either `"asc"` (ascending) or `"desc"` (descending)
- `priority`: Sort priority when multiple sort keys are defined (lower numbers have higher priority)

### Column Configuration Options

Each column in the `columns` array can have the following properties:

| Property | Description | Default | Options |
|----------|-------------|---------|---------|
| `header` | Column header text | (required) | Any string |
| `key` | JSON field name in the data | Derived from header | Any string |
| `justification` | Text alignment | `"left"` | `"left"`, `"right"`, `"center"` |
| `datatype` | Data type for validation and formatting | `"text"` | `"text"`, `"int"`, `"float"`, `"kcpu"`, `"kmem"` |
| `null_value` | How to display null values | `"blank"` | `"blank"`, `"0"`, `"missing"` |
| `zero_value` | How to display zero values | `"blank"` | `"blank"`, `"0"`, `"missing"` |
| `total` | Type of total to calculate | `"none"` | See "Total Types" section |
| `break` | Insert separator when value changes | `false` | `true`, `false` |
| `string_limit` | Maximum string length | `0` (unlimited) | Any integer |
| `wrap_mode` | How to handle text exceeding limit | `"clip"` | `"clip"`, `"wrap"` |
| `wrap_char` | Character to use for wrapping | `""` | Any character |
| `padding` | Padding spaces on each side | `1` | Any integer |

## Supported Data Types

Tables.sh supports the following data types:

### text

Text data with optional wrapping and length limits.

- **Validation**: Any non-null text value
- **Formatting**: Raw text with optional clipping/wrapping
- **Total Types**: `count`, `unique`

### int / float

Integer or floating-point numbers.

- **Validation**: Any valid number
- **Formatting**: Raw number or custom format string
- **Total Types**: `sum`, `min`, `max`, `count`, `unique`

### kcpu

Kubernetes-style CPU values (e.g., `100m` for 100 millicores).

- **Validation**: Values with `m` suffix or numeric values
- **Formatting**: Always with `m` suffix
- **Total Types**: `sum`, `count`

### kmem

Kubernetes-style memory values (e.g., `128M`, `1G`, `512Ki`).

- **Validation**: Values with `K`, `M`, `G`, `Ki`, `Mi`, `Gi` suffixes
- **Formatting**: Normalized to `K`, `M`, or `G` format
- **Total Types**: `sum`, `count`

## Total Types

Depending on the data type, the following total calculations are available:

- `sum`: Sum of all values (numeric types, kcpu, kmem)
- `min`: Minimum value (numeric types)
- `max`: Maximum value (numeric types)
- `count`: Count of non-null values (all types)
- `unique`: Count of unique values (all types)
- `none`: No total (default)

## Examples

### Basic Example

This example renders a table of Kubernetes pod information:

**Layout JSON (layout.json):**
```json
{
  "theme": "Red",
  "columns": [
    {
      "header": "POD",
      "key": "pod",
      "justification": "left",
      "datatype": "text"
    },
    {
      "header": "NAMESPACE",
      "key": "namespace",
      "justification": "center",
      "datatype": "text"
    },
    {
      "header": "CPU USE",
      "key": "cpu_use",
      "justification": "right",
      "datatype": "kcpu",
      "total": "sum"
    }
  ]
}
```

**Data JSON (data.json):**
```json
[
  {
    "pod": "pod-a",
    "namespace": "default",
    "cpu_use": "100m"
  },
  {
    "pod": "pod-b",
    "namespace": "kube-system",
    "cpu_use": "50m"
  }
]
```

**Command:**
```bash
./tables.sh layout.json data.json
```

**Output:**
```
╭───────────┬────────────┬─────────╮
│POD        │ NAMESPACE  │  CPU USE│
├───────────┼────────────┼─────────┤
│pod-a      │  default   │     100m│
│pod-b      │kube-system │      50m│
├───────────┼────────────┼─────────┤
│           │            │     150m│
╰───────────┴────────────┴─────────╯
```

### Advanced Example

This example demonstrates more features, including sorting, text wrapping, and data grouping:

**Layout JSON:**
```json
{
  "theme": "Blue",
  "sort": [
    {"key": "namespace", "direction": "asc", "priority": 1},
    {"key": "pod", "direction": "asc", "priority": 2}
  ],
  "columns": [
    {
      "header": "POD",
      "key": "pod",
      "justification": "left",
      "datatype": "text",
      "total": "count"
    },
    {
      "header": "NAMESPACE",
      "key": "namespace",
      "justification": "center",
      "datatype": "text",
      "break": true
    },
    {
      "header": "CPU USE",
      "key": "cpu_use",
      "justification": "right",
      "datatype": "kcpu",
      "null_value": "missing",
      "total": "sum"
    },
    {
      "header": "MEM USE",
      "key": "mem_use",
      "justification": "right",
      "datatype": "kmem",
      "zero_value": "0",
      "total": "sum"
    },
    {
      "header": "PORTS",
      "key": "ports",
      "justification": "left",
      "datatype": "text",
      "string_limit": 15,
      "wrap_mode": "wrap",
      "wrap_char": ";"
    }
  ]
}
```

**Data JSON:**
```json
[
  {
    "pod": "pod-a",
    "namespace": "ns1",
    "cpu_use": "100m",
    "mem_use": "128M",
    "ports": "8080/TCP;8443/TCP"
  },
  {
    "pod": "pod-b",
    "namespace": "ns1",
    "cpu_use": "50m",
    "mem_use": "64M",
    "ports": "80/TCP"
  },
  {
    "pod": "pod-c",
    "namespace": "ns2",
    "cpu_use": null,
    "mem_use": "256M",
    "ports": ""
  },
  {
    "pod": "pod-d",
    "namespace": "ns2",
    "cpu_use": "200m",
    "mem_use": null,
    "ports": "9090/TCP;9091/TCP;9092/TCP"
  }
]
```

**Output:**
```
╭───────────┬────────────┬─────────┬─────────┬───────────────╮
│POD        │ NAMESPACE  │  CPU USE│  MEM USE│PORTS          │
├───────────┼────────────┼─────────┼─────────┼───────────────┤
│pod-a      │    ns1     │     100m│     128M│8080/TCP       │
│           │            │         │         │8443/TCP       │
│pod-b      │            │      50m│      64M│80/TCP         │
├───────────┼────────────┼─────────┼─────────┼───────────────┤
│pod-c      │    ns2     │  Missing│     256M│               │
│pod-d      │            │     200m│  Missing│9090/TCP       │
│           │            │         │         │9091/TCP       │
│           │            │         │         │9092/TCP       │
├───────────┼────────────┼─────────┼─────────┼───────────────┤
│4          │            │     350m│     448M│               │
╰───────────┴────────────┴─────────┴─────────┴───────────────╯
```

## Using in Scripts

You can source tables.sh in your own scripts to use its functions:

```bash
#!/usr/bin/env bash

# Source table library
source ./tables.sh

# Create layout and data files
cat > layout.json << 'EOF'
{
  "theme": "Red",
  "columns": [
    {
      "header": "NAME",
      "key": "name",
      "datatype": "text"
    },
    {
      "header": "VALUE",
      "key": "value",
      "datatype": "int"
    }
  ]
}
EOF

cat > data.json << 'EOF'
[
  {"name": "Item A", "value": 10},
  {"name": "Item B", "value": 20}
]
EOF

# Draw the table
draw_table layout.json data.json
```

## Tips and Best Practices

1. **Column Width Management**:
   - The script automatically determines column widths based on content
   - Use `string_limit` and `wrap_mode` for wide columns

2. **Data Sorting**:
   - Complex sorting can be achieved with multiple sort keys and priorities
   - Use `break: true` to visually group data by important fields

3. **Null and Zero Handling**:
   - Choose appropriate `null_value` and `zero_value` settings for each column
   - Options include showing blank space, "0", or "Missing"

4. **Performance**:
   - Very large datasets may cause performance issues
   - Consider limiting data or pre-filtering for large datasets

5. **Color Compatibility**:
   - The colored output uses ANSI escape sequences which work in most terminals
   - For environments without color support, consider piping through `cat -A` to see escape sequences