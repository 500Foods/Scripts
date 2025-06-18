#!/usr/bin/env bash

# Test script for footer position feature
# Creates tables with same data but different footer positions

# Create layout JSON files with different footer position settings
cat > layout_none.json << EOF
{
  "footer": "Kubernetes Pod Resources Summary",
  "footer_position": "none",
  "columns": [
    { "header": "Pod Name", "width": 35 },
    { "header": "CPU", "width": 8, "justification": "right" },
    { "header": "MEM", "width": 8, "justification": "right" }
  ]
}
EOF

cat > layout_left.json << EOF
{
  "footer": "Kubernetes Pod Resources Summary",
  "footer_position": "left",
  "columns": [
    { "header": "Pod Name", "width": 35 },
    { "header": "CPU", "width": 8, "justification": "right" },
    { "header": "MEM", "width": 8, "justification": "right" }
  ]
}
EOF

cat > layout_right.json << EOF
{
  "footer": "Kubernetes Pod Resources Summary",
  "footer_position": "right",
  "columns": [
    { "header": "Pod Name", "width": 35 },
    { "header": "CPU", "width": 8, "justification": "right" },
    { "header": "MEM", "width": 8, "justification": "right" }
  ]
}
EOF

cat > layout_center.json << EOF
{
  "footer": "Kubernetes Pod Resources Summary",
  "footer_position": "center",
  "columns": [
    { "header": "Pod Name", "width": 35 },
    { "header": "CPU", "width": 8, "justification": "right" },
    { "header": "MEM", "width": 8, "justification": "right" }
  ]
}
EOF

# Layout with a longer footer to demonstrate clipping
cat > layout_long_footer.json << EOF
{
  "footer": "Kubernetes Pod Resource Usage Metrics Dashboard - Production Cluster Overview Summary Report",
  "footer_position": "center",
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

# Run tests with each footer position setting
echo "Test 1: Default footer position (none)"
echo "----------------------------------------"
./tables.sh layout_none.json data.json

echo "Test 2: Left-aligned footer"
echo "----------------------------------------"
./tables.sh layout_left.json data.json

echo "Test 3: Right-aligned footer"
echo "----------------------------------------"
./tables.sh layout_right.json data.json

echo "Test 4: Center-aligned footer"
echo "----------------------------------------"
./tables.sh layout_center.json data.json

echo "Test 5: Long footer with clipping (center-aligned)"
echo "----------------------------------------"
./tables.sh layout_long_footer.json data.json

# Clean up temporary files
rm -f layout_*.json data.json
