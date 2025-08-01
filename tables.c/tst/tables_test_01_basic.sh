#!/usr/bin/env bash

# Test Suite 1: Basic - Various datatypes and justifications without headers, footers, or summaries
# This test suite focuses on demonstrating the core table drawing functionality
# with different datatypes (text, int, num, float, kcpu, kmem) and justifications (left, right, center)

# Create temporary files for our JSON
layout_file=$(mktemp)
data_file=$(mktemp)
tables_script="$(dirname "$0")/../tables"

# Cleanup function
cleanup() {
    rm -f "$layout_file" "$data_file"
}
trap cleanup EXIT

# Check for debug flags
DEBUG_FLAG=""
DEBUG_LAYOUT_FLAG=""
if [[ "$1" == "--debug" ]]; then
    DEBUG_FLAG="--debug"
    echo "Debug mode enabled"
elif [[ "$1" == "--debug_layout" ]]; then
    DEBUG_LAYOUT_FLAG="--debug_layout"
    echo "Debug layout mode enabled"
elif [[ "$1" == "--debug" && "$2" == "--debug_layout" ]]; then
    DEBUG_FLAG="--debug"
    DEBUG_LAYOUT_FLAG="--debug_layout"
    echo "Debug and Debug layout modes enabled"
elif [[ "$1" == "--debug_layout" && "$2" == "--debug" ]]; then
    DEBUG_FLAG="--debug"
    DEBUG_LAYOUT_FLAG="--debug_layout"
    echo "Debug and Debug layout modes enabled"
fi

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
    "status": "Running"
  },
  {
    "id": 2,
    "name": "db-server-01",
    "cpu_cores": 8,
    "load_avg": 5.12,
    "cpu_usage": "3200m",
    "memory_usage": "8192Mi", 
    "status": "Running"
  },
  {
    "id": 3,
    "name": "cache-server",
    "cpu_cores": 2,
    "load_avg": 0.85,
    "cpu_usage": "500m",
    "memory_usage": "1024Mi",
    "status": "Starting"
  },
  {
    "id": 4,
    "name": "api-gateway",
    "cpu_cores": 6,
    "load_avg": 3.21,
    "cpu_usage": "2100m",
    "memory_usage": "4096Mi",
    "status": "{YELLOW}Running{RESET}"
  }
]
EOF

# Test 1-A: Integer and Text datatypes with different justifications (Theme: Red)
cat > "$layout_file" << 'EOF'
{
  "theme": "Red",
  "columns": [
    {
      "header": "ID",
      "key": "id",
      "datatype": "int",
      "justification": "right"
    },
    {
      "header": "ID2",
      "key": "id",
      "datatype": "int",
      "justification": "right",
      "visible": false
    },
    {
      "header": "Server Name", 
      "key": "name",
      "datatype": "text",
      "justification": "left"
    },
    {
      "header": "Status",
      "key": "status", 
      "datatype": "text",
      "justification": "center"
    }
  ]
}
EOF

echo "TestC 1-A: Integer and Text datatypes with different justifications"
echo "------------------------------------------------------------------"
"$tables_script" "$layout_file" "$data_file" $DEBUG_FLAG $DEBUG_LAYOUT_FLAG


# Test 1-B: Numeric datatypes - int, num, float (Theme: Blue)
cat > "$layout_file" << 'EOF'
{
  "theme": "Blue",
  "columns": [
    {
      "header": "ID",
      "key": "id", 
      "datatype": "int",
      "justification": "right"
    },
    {
      "header": "CPU Cores",
      "key": "cpu_cores",
      "datatype": "num", 
      "justification": "right"
    },
    {
      "header": "Load Average",
      "key": "load_avg",
      "datatype": "float",
      "justification": "right"
    }
  ]
}
EOF

echo -e "\nTestC 1-B: Numeric datatypes - int, num, float"
echo "-----------------------------------------------"
"$tables_script" "$layout_file" "$data_file" $DEBUG_FLAG $DEBUG_LAYOUT_FLAG

# Test 1-C: Kubernetes resource datatypes - kcpu and kmem (Theme: Red)
cat > "$layout_file" << 'EOF'
{
  "theme": "Red", 
  "columns": [
    {
      "header": "Server",
      "key": "name",
      "datatype": "text",
      "justification": "left"
    },
    {
      "header": "CPU Usage",
      "key": "cpu_usage", 
      "datatype": "kcpu",
      "justification": "right"
    },
    {
      "header": "Memory Usage", 
      "key": "memory_usage",
      "datatype": "kmem",
      "justification": "right"
    }
  ]
}
EOF

echo -e "\nTestC 1-C: Kubernetes resource datatypes - kcpu and kmem"
echo "---------------------------------------------------------"
"$tables_script" "$layout_file" "$data_file" $DEBUG_FLAG $DEBUG_LAYOUT_FLAG

# Test 1-D: Mixed datatypes with center justification focus (Theme: Blue)
cat > "$layout_file" << 'EOF'
{
  "theme": "Blue",
  "columns": [
    {
      "header": "ID",
      "key": "id",
      "datatype": "int", 
      "justification": "center"
    },
    {
      "header": "Status",
      "key": "status",
      "datatype": "text",
      "justification": "center"
    },
    {
      "header": "Load",
      "key": "load_avg", 
      "datatype": "float",
      "justification": "center"
    }
  ]
}
EOF

echo -e "\nTestC 1-D: Mixed datatypes with center justification focus"
echo "-----------------------------------------------------------"
"$tables_script" "$layout_file" "$data_file" $DEBUG_FLAG $DEBUG_LAYOUT_FLAG

# Test 1-E: All datatypes in single table (Theme: Red)
cat > "$layout_file" << 'EOF'
{
  "theme": "Red",
  "columns": [
    {
      "header": "ID",
      "key": "id",
      "datatype": "int",
      "justification": "right"
    },
    {
      "header": "Name",
      "key": "name", 
      "datatype": "text",
      "justification": "left"
    },
    {
      "header": "Cores",
      "key": "cpu_cores",
      "datatype": "num",
      "justification": "right"
    },
    {
      "header": "Load",
      "key": "load_avg",
      "datatype": "float", 
      "justification": "right"
    },
    {
      "header": "CPU",
      "key": "cpu_usage",
      "datatype": "kcpu",
      "justification": "right"
    },
    {
      "header": "Memory", 
      "key": "memory_usage",
      "datatype": "kmem",
      "justification": "right"
    }
  ]
}
EOF

echo -e "\nTestC 1-E: All datatypes in single table"
echo "-----------------------------------------"
"$tables_script" "$layout_file" "$data_file" $DEBUG_FLAG $DEBUG_LAYOUT_FLAG

# Test 1-F: Text datatype with different justifications (Theme: Blue)
cat > "$layout_file" << 'EOF'
{
  "theme": "Blue",
  "columns": [
    {
      "header": "Left Text",
      "key": "name",
      "datatype": "text",
      "justification": "left"
    },
    {
      "header": "Center Text",
      "key": "status", 
      "datatype": "text",
      "justification": "center"
    },
    {
      "header": "Right Text",
      "key": "name",
      "datatype": "text",
      "justification": "right"
    }
  ]
}
EOF

echo -e "\nTestC 1-F: Text datatype with different justifications"
echo "-------------------------------------------------------"
"$tables_script" "$layout_file" "$data_file" $DEBUG_FLAG $DEBUG_LAYOUT_FLAG

# Test 1-G: Color placeholders with width constraints (Color Clipping Test)
cat > "$data_file" << 'EOF'
[
  {
    "name": "{GREEN}Success Item{RESET}",
    "status": "{WHITE}Processing{RESET}",
    "value": 100
  },
  {
    "name": "{RED}Error Item{RESET}",
    "status": "{YELLOW}Warning Status{RESET}",
    "value": 250
  },
  {
    "name": "{BLUE}Info Item{RESET}",
    "status": "{CYAN}Ready{RESET}",
    "value": 75
  },
  {
    "name": "{WHITE}Bright Item{RESET}",
    "status": "{MAGENTA}Special{RESET}",
    "value": 999
  }
]
EOF

cat > "$layout_file" << 'EOF'
{
  "theme": "Red",
  "title": "Color Test - {WHITE}WHITE{RESET} and {RED}RED{RESET} in Title",
  "title_position": "center",
  "columns": [
    {
      "header": "Name",
      "key": "name",
      "justification": "left",
      "datatype": "text",
      "width": 20
    },
    {
      "header": "Status",
      "key": "status", 
      "justification": "center",
      "datatype": "text",
      "width": 25
    },
    {
      "header": "Value",
      "key": "value",
      "justification": "right", 
      "datatype": "int",
      "width": 15
    }
  ]
}
EOF

echo -e "\nTestC 1-G: Color placeholders with width constraints (Current Bug Fix Test)"
echo "----------------------------------------------------------------------------"
"$tables_script" "$layout_file" "$data_file" $DEBUG_FLAG $DEBUG_LAYOUT_FLAG

# Test 1-H: Color clipping with different justifications
cat > "$data_file" << 'EOF'
[
  {
    "left_text": "{RED}This is a very long red text that will be clipped{RESET}",
    "center_text": "{BLUE}This is a very long blue text that will be clipped{RESET}",
    "right_text": "{GREEN}This is a very long green text that will be clipped{RESET}"
  },
  {
    "left_text": "{YELLOW}Short{RESET}",
    "center_text": "{CYAN}Medium text{RESET}",
    "right_text": "{MAGENTA}Longer text here{RESET}"
  },
  {
    "left_text": "No colors here",
    "center_text": "{WHITE}Mixed {RED}colors {BLUE}in {GREEN}one{RESET}",
    "right_text": "{BOLD}{UNDERLINE}Formatted text{RESET}"
  }
]
EOF

cat > "$layout_file" << 'EOF'
{
  "theme": "Blue",
  "title": "{BOLD}Color Clipping Test with Different Justifications{RESET}",
  "title_position": "center",
  "columns": [
    {
      "header": "Left Clipped",
      "key": "left_text",
      "justification": "left",
      "datatype": "text",
      "width": 25
    },
    {
      "header": "Center Clipped",
      "key": "center_text", 
      "justification": "center",
      "datatype": "text",
      "width": 25
    },
    {
      "header": "Right Clipped",
      "key": "right_text",
      "justification": "right", 
      "datatype": "text",
      "width": 25
    }
  ]
}
EOF

echo -e "\nTestC 1-H: Color clipping with different justifications"
echo "--------------------------------------------------------"
"$tables_script" "$layout_file" "$data_file" $DEBUG_FLAG $DEBUG_LAYOUT_FLAG

# Test 1-I: Complex color combinations and edge cases
cat > "$data_file" << 'EOF'
[
  {
    "simple": "{RED}Red{RESET}",
    "nested": "{BOLD}{RED}Bold Red{RESET}{RESET}",
    "multiple": "{RED}R{GREEN}G{BLUE}B{RESET}",
    "mixed": "Start {YELLOW}Yellow{RESET} End"
  },
  {
    "simple": "Plain text",
    "nested": "{UNDERLINE}{CYAN}Underlined Cyan{RESET}",
    "multiple": "{WHITE}{BOLD}Bold White{RESET}",
    "mixed": "{DIM}Dim{RESET} and {BRIGHT}Bright{RESET}"
  },
  {
    "simple": "{GREEN}Very long green text that should be clipped{RESET}",
    "nested": "No color but very long text that should also be clipped",
    "multiple": "{RED}A{BLUE}B{GREEN}C{YELLOW}D{CYAN}E{MAGENTA}F{RESET}",
    "mixed": "Mix of {RED}red{RESET} and normal text here"
  }
]
EOF

cat > "$layout_file" << 'EOF'
{
  "theme": "Red",
  "title": "{GREEN}Complex Color Test{RESET} - {BOLD}Edge Cases{RESET}",
  "title_position": "full",
  "columns": [
    {
      "header": "Simple",
      "key": "simple",
      "justification": "left",
      "datatype": "text",
      "width": 15
    },
    {
      "header": "Nested",
      "key": "nested", 
      "justification": "center",
      "datatype": "text",
      "width": 20
    },
    {
      "header": "Multiple",
      "key": "multiple",
      "justification": "right", 
      "datatype": "text",
      "width": 18
    },
    {
      "header": "Mixed Content",
      "key": "mixed",
      "justification": "left", 
      "datatype": "text",
      "width": 22
    }
  ]
}
EOF

echo -e "\nTestC 1-I: Complex color combinations and edge cases"
echo "-----------------------------------------------------"
"$tables_script" "$layout_file" "$data_file" $DEBUG_FLAG $DEBUG_LAYOUT_FLAG
