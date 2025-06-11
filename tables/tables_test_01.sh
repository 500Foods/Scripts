#!/usr/bin/env bash

# tables_test.sh: Test script for tables.sh
# Usage: ./tables_test.sh [--debug] [--version]
# Tests rendering of a sample table with Kubernetes-style data

set -uo pipefail

# Source table library
if [[ ! -f "tables.sh" ]]; then
    echo -e "\033[0;31mError: tables.sh not found\033[0m" >&2
    exit 1
fi
source tables.sh

# Parse arguments
DEBUG=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) DEBUG=true; shift ;;
        --version) draw_table "" "" --version; exit 0 ;;
        *) echo -e "\033[0;31mError: Unknown option: $1\033[0m" >&2; exit 1 ;;
    esac
done

# Create sample layout JSON
cat > layout.json << 'EOF'
{
  "theme": "Red",
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
      "null_value": "blank",
      "zero_value": "blank",
      "total": "count"
    },
    {
      "header": "NAMESPACE",
      "key": "namespace",
      "justification": "center",
      "datatype": "text",
      "null_value": "blank",
      "zero_value": "blank",
      "total": "count",
      "break": true
    },
    {
      "header": "CPU USE",
      "key": "cpu_use",
      "justification": "right",
      "datatype": "kcpu",
      "null_value": "blank",
      "zero_value": "blank",
      "total": "sum"
    },
    {
      "header": "MEM USE",
      "key": "mem_use",
      "justification": "right",
      "datatype": "kmem",
      "null_value": "blank",
      "zero_value": "blank",
      "total": "sum"
    },
    {
      "header": "PORTS",
      "key": "ports",
      "justification": "left",
      "datatype": "text",
      "null_value": "blank",
      "zero_value": "blank",
      "total": "none",
      "string_limit": 20,
      "wrap_mode": "wrap",
      "wrap_char": ";"
    }
  ]
}
EOF

# Create sample data JSON
cat > data.json << 'EOF'
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
  },
  {
    "pod": "pod-e",
    "namespace": "ns3",
    "cpu_use": "0m",
    "mem_use": "0M",
    "ports": null
  },
  {
    "pod": "pod-f",
    "namespace": "ns3",
    "cpu_use": "150m",
    "mem_use": "512M",
    "ports": "443/TCP;8443/TCP;9443/TCP"
  }
]
EOF

# Run the table drawing
echo "Rendering test table..."
draw_table layout.json data.json ${DEBUG:+--debug} 2>debug_output.txt

# Show debug output status
[[ "$DEBUG" == "true" ]] && echo "Debug output saved to debug_output.txt"

# Clean up
# rm -f layout.json data.json
