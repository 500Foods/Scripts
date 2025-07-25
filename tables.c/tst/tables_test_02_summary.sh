#!/usr/bin/env bash

# Test Suite 2: Summary - Summary row functionality with various summary functions
# This test suite focuses on demonstrating the summary row functionality
# with different summary types (sum, count, min, max, unique) across all datatypes

# Create temporary files for our JSON
layout_file=$(mktemp)
data_file=$(mktemp)
tables_script="$(dirname "$0")/../tables"

# Cleanup function
cleanup() {
    rm -f "$layout_file" "$data_file"
}
trap cleanup EXIT

# Setup comprehensive test data showcasing all datatypes
cat > "$data_file" << 'EOF'
[
  {
    "id": 1,
    "name": "web-server-01",
    "cpu_cores": 4,
    "load_avg": 2.45,
    "cpu_usage": "1250m",
    "memory_usage": "2048Mi",
    "status": "Running",
    "test_int": 100,
    "test_float": 1.23,
    "test_string": "hello"
  },
  {
    "id": 2,
    "name": "db-server-01",
    "cpu_cores": 8,
    "load_avg": 5.12,
    "cpu_usage": "3200m",
    "memory_usage": "8192Mi", 
    "status": "Running",
    "test_int": 0,
    "test_float": 0.0,
    "test_string": ""
  },
  {
    "id": 3,
    "name": "cache-server",
    "cpu_cores": 2,
    "load_avg": 0.85,
    "cpu_usage": "500m",
    "memory_usage": "1024Mi",
    "status": "Starting",
    "test_int": null,
    "test_float": null,
    "test_string": null
  },
  {
    "id": 4,
    "name": "api-gateway",
    "cpu_cores": 6,
    "load_avg": 3.21,
    "cpu_usage": "2100m",
    "memory_usage": "4096Mi",
    "status": "Running",
    "test_int": 200,
    "test_float": 4.56,
    "test_string": "world"
  },
  {
    "id": 5,
    "name": "backup-server",
    "cpu_cores": 4,
    "load_avg": 1.5,
    "cpu_usage": "0m",
    "memory_usage": "0Mi",
    "status": "Idle",
    "test_int": 0,
    "test_float": 0.00,
    "test_string": ""
  }
]
EOF

# Test 2-A: Basic sum and count summaries (Theme: Red)
cat > "$layout_file" << 'EOF'
{
  "theme": "Red",
  "columns": [
    {
      "header": "ID",
      "key": "id",
      "datatype": "int",
      "justification": "right",
      "summary": "sum"
    },
    {
      "header": "Server Name", 
      "key": "name",
      "datatype": "text",
      "justification": "left",
      "summary": "count"
    },
    {
      "header": "CPU Cores",
      "key": "cpu_cores",
      "datatype": "num",
      "justification": "right",
      "summary": "sum"
    }
  ]
}
EOF

echo "TestC 2-A: Basic sum and count summaries"
echo "-----------------------------------------"
"$tables_script" "$layout_file" "$data_file"

# Test 2-B: Min and max summaries for numeric types (Theme: Blue)
cat > "$layout_file" << 'EOF'
{
  "theme": "Blue",
  "columns": [
    {
      "header": "ID",
      "key": "id",
      "datatype": "int",
      "justification": "right",
      "summary": "min"
    },
    {
      "header": "CPU Cores",
      "key": "cpu_cores",
      "datatype": "num", 
      "justification": "right",
      "summary": "max"
    },
    {
      "header": "Load Average",
      "key": "load_avg",
      "datatype": "float",
      "justification": "right",
      "summary": "min"
    }
  ]
}
EOF

echo -e "\nTestC 2-B: Min and max summaries for numeric types"
echo "----------------------------------------------------"
"$tables_script" "$layout_file" "$data_file"

# Test 2-C: Kubernetes resource summaries - kcpu and kmem (Theme: Red)
cat > "$layout_file" << 'EOF'
{
  "theme": "Red", 
  "columns": [
    {
      "header": "Server",
      "key": "name",
      "datatype": "text",
      "justification": "left",
      "summary": "count"
    },
    {
      "header": "CPU Usage",
      "key": "cpu_usage", 
      "datatype": "kcpu",
      "justification": "right",
      "summary": "sum"
    },
    {
      "header": "Memory Usage", 
      "key": "memory_usage",
      "datatype": "kmem",
      "justification": "right",
      "summary": "sum"
    }
  ]
}
EOF

echo -e "\nTestC 2-C: Kubernetes resource summaries - kcpu and kmem"
echo "---------------------------------------------------------"
"$tables_script" "$layout_file" "$data_file"

# Test 2-D: Unique value summaries (Theme: Blue)
cat > "$layout_file" << 'EOF'
{
  "theme": "Blue",
  "columns": [
    {
      "header": "Status",
      "key": "status",
      "datatype": "text", 
      "justification": "center",
      "summary": "unique"
    },
    {
      "header": "CPU Cores",
      "key": "cpu_cores",
      "datatype": "num",
      "justification": "right",
      "summary": "unique"
    },
    {
      "header": "Load Average",
      "key": "load_avg", 
      "datatype": "float",
      "justification": "right",
      "summary": "avg"
    }
  ]
}
EOF

echo -e "\nTestC 2-D: Unique value summaries"
echo "-----------------------------------"
"$tables_script" "$layout_file" "$data_file"

# Test 2-E: Mixed summaries across all datatypes (Theme: Red)
cat > "$layout_file" << 'EOF'
{
  "theme": "Red",
  "columns": [
    {
      "header": "ID",
      "key": "id",
      "datatype": "int",
      "justification": "right",
      "summary": "sum"
    },
    {
      "header": "Name",
      "key": "name", 
      "datatype": "text",
      "justification": "left",
      "summary": "count"
    },
    {
      "header": "Cores",
      "key": "cpu_cores",
      "datatype": "num",
      "justification": "right",
      "summary": "max"
    },
    {
      "header": "Load",
      "key": "load_avg",
      "datatype": "float", 
      "justification": "right",
      "summary": "min"
    },
    {
      "header": "CPU",
      "key": "cpu_usage",
      "datatype": "kcpu",
      "justification": "right",
      "summary": "sum"
    },
    {
      "header": "Memory", 
      "key": "memory_usage",
      "datatype": "kmem",
      "justification": "right",
      "summary": "sum"
    }
  ]
}
EOF

echo -e "\nTestC 2-E: Mixed summaries across all datatypes"
echo "-------------------------------------------------"
"$tables_script" "$layout_file" "$data_file"

# Test 2-F: No summaries vs summaries comparison (Theme: Blue)
cat > "$layout_file" << 'EOF'
{
  "theme": "Blue",
  "columns": [
    {
      "header": "Server Name",
      "key": "name",
      "datatype": "text",
      "justification": "left",
      "summary": "none"
    },
    {
      "header": "Status", 
      "key": "status",
      "datatype": "text",
      "justification": "center",
      "summary": "unique"
    },
    {
      "header": "Total CPU",
      "key": "cpu_usage",
      "datatype": "kcpu",
      "justification": "right",
      "summary": "sum"
    }
  ]
}
EOF

echo -e "\nTestC 2-F: No summaries vs summaries comparison"
echo "-------------------------------------------------"
"$tables_script" "$layout_file" "$data_file"

# Test 2-G: All available summary types for numeric data (Theme: Red)
cat > "$layout_file" << 'EOF'
{
  "theme": "Red",
  "columns": [
    {
      "header": "Sum",
      "key": "cpu_cores",
      "datatype": "int",
      "justification": "right",
      "summary": "sum"
    },
    {
      "header": "Min",
      "key": "cpu_cores",
      "datatype": "int",
      "justification": "right",
      "summary": "min"
    },
    {
      "header": "Max",
      "key": "cpu_cores", 
      "datatype": "int",
      "justification": "right",
      "summary": "max"
    },
    {
      "header": "Avg",
      "key": "cpu_cores",
      "datatype": "int",
      "justification": "right",
      "summary": "avg"
    },
    {
      "header": "Count",
      "key": "cpu_cores",
      "datatype": "int",
      "justification": "right",
      "summary": "count"
    },
    {
      "header": "Unique",
      "key": "cpu_cores",
      "datatype": "int",
      "justification": "right",
      "summary": "unique"
    }
  ]
}
EOF

echo -e "\nTestC 2-G: All available summary types for numeric data"
echo "---------------------------------------------------------"
"$tables_script" "$layout_file" "$data_file"

# Test 2-H: All available summary types for floating point data (Theme: Blue)
cat > "$layout_file" << 'EOF'
{
  "theme": "Blue",
  "columns": [
    {
      "header": "Sum",
      "key": "load_avg",
      "datatype": "float",
      "justification": "right",
      "summary": "sum"
    },
    {
      "header": "Min",
      "key": "load_avg",
      "datatype": "float",
      "justification": "right",
      "summary": "min"
    },
    {
      "header": "Max",
      "key": "load_avg", 
      "datatype": "float",
      "justification": "right",
      "summary": "max"
    },
    {
      "header": "Avg",
      "key": "load_avg",
      "datatype": "float",
      "justification": "right",
      "summary": "avg"
    },
    {
      "header": "Count",
      "key": "load_avg",
      "datatype": "float",
      "justification": "right",
      "summary": "count"
    },
    {
      "header": "Unique",
      "key": "load_avg",
      "datatype": "float",
      "justification": "right",
      "summary": "unique"
    }
  ]
}
EOF

echo -e "\nTestC 2-H: All available summary types for floating point data"
echo "---------------------------------------------------------------"
"$tables_script" "$layout_file" "$data_file"

# Test 2-I: Blanks and nonblanks summaries
cat > "$layout_file" << 'EOF'
{
  "theme": "Red",
  "columns": [
    {
      "header": "Test Int",
      "key": "test_int",
      "datatype": "int",
      "justification": "right",
      "summary": "blanks"
    },
    {
      "header": "Test Float",
      "key": "test_float",
      "datatype": "float",
      "justification": "right",
      "summary": "nonblanks"
    },
    {
      "header": "Test String",
      "key": "test_string",
      "datatype": "text",
      "justification": "left",
      "summary": "blanks"
    },
    {
      "header": "Status",
      "key": "status",
      "datatype": "text",
      "justification": "left",
      "summary": "nonblanks"
    }
  ]
}
EOF

echo -e "\nTestC 2-I: Blanks and nonblanks summaries"
echo "------------------------------------------"
"$tables_script" "$layout_file" "$data_file"
