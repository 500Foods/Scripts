#!/usr/bin/env bash

# Test script for title position feature
# Creates tables with same data but different title positions

# Create layout JSON files with different title position settings
cat > layout_none.json << EOF
{
  "title": "Kubernetes Pod Resources",
  "title_position": "none",
  "columns": [
    { "header": "Pod Name", "width": 35 },
    { "header": "CPU", "width": 8, "justification": "right" },
    { "header": "MEM", "width": 8, "justification": "right" }
  ]
}
EOF

cat > layout_left.json << EOF
{
  "title": "Kubernetes Pod Resources",
  "title_position": "left",
  "columns": [
    { "header": "Pod Name", "width": 35 },
    { "header": "CPU", "width": 8, "justification": "right" },
    { "header": "MEM", "width": 8, "justification": "right" }
  ]
}
EOF

cat > layout_right.json << EOF
{
  "title": "Kubernetes Pod Resources",
  "title_position": "right",
  "columns": [
    { "header": "Pod Name", "width": 35 },
    { "header": "CPU", "width": 8, "justification": "right" },
    { "header": "MEM", "width": 8, "justification": "right" }
  ]
}
EOF

cat > layout_center.json << EOF
{
  "title": "Kubernetes Pod Resources",
  "title_position": "center",
  "columns": [
    { "header": "Pod Name", "width": 35 },
    { "header": "CPU", "width": 8, "justification": "right" },
    { "header": "MEM", "width": 8, "justification": "right" }
  ]
}
EOF

# Layout with a longer title to demonstrate clipping
cat > layout_long_title.json << EOF
{
  "title": "Kubernetes Pod Resource Usage Metrics Dashboard - Production Cluster Overview",
  "title_position": "center",
  "columns": [
    { "header": "Pod Name", "width": 35 },
    { "header": "CPU", "width": 8, "justification": "right" },
    { "header": "MEM", "width": 8, "justification": "right" }
  ]
}
EOF

# Create data JSON
cat > data.json << EOF
[
  { "pod_name": "coredns-787d4b4b6c-abcd1", "cpu": "100m", "mem": "70M" },
  { "pod_name": "coredns-787d4b4b6c-abcd2", "cpu": "100m", "mem": "70M" },
  { "pod_name": "nginx-deployment-66b6c48dd5-efgh1", "cpu": "750m", "mem": "768M" },
  { "pod_name": "nginx-deployment-66b6c48dd5-efgh2", "cpu": "750m", "mem": "768M" }
]
EOF

# Run tests with each title position setting
echo "Test 1: Default title position (none)"
echo "----------------------------------------"
./tables.sh layout_none.json data.json

echo "Test 2: Left-aligned title"
echo "----------------------------------------"
./tables.sh layout_left.json data.json

echo "Test 3: Right-aligned title"
echo "----------------------------------------"
./tables.sh layout_right.json data.json

echo "Test 4: Center-aligned title"
echo "----------------------------------------"
./tables.sh layout_center.json data.json

echo "Test 5: Long title with clipping (center-aligned)"
echo "----------------------------------------"
./tables.sh layout_long_title.json data.json

# Clean up temporary files
rm -f layout_*.json data.json