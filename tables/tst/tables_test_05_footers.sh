#!/usr/bin/env bash

# Create temporary files for our JSON
layout_file=$(mktemp)
data_file=$(mktemp)

# Setup the test data we'll use across all tests
cat > "$data_file" << 'EOF'
[
  {
    "namespace": "kube-system",
    "pod_name": "coredns-787d4b4b6c-abcd1",
    "cpu": "100m",
    "memory": "70Mi"
  },
  {
    "namespace": "kube-system",
    "pod_name": "coredns-787d4b4b6c-abcd2",
    "cpu": "100m",
    "memory": "70Mi"
  },
  {
    "namespace": "default",
    "pod_name": "nginx-deployment-66b6c48dd5-efgh1",
    "cpu": "750m",
    "memory": "768Mi"
  },
  {
    "namespace": "default",
    "pod_name": "nginx-deployment-66b6c48dd5-efgh2",
    "cpu": "750m",
    "memory": "768Mi"
  }
]
EOF

# Test 1: Short footer - Footer shorter than first column width
cat > "$layout_file" << 'EOF'
{
  "footer": "Pod Stats",
  "theme": "Red",
  "columns": [
    {
      "header": "Pod Name",
      "key": "pod_name",
      "datatype": "text",
      "total": "count",
      "width": 35
    },
    {
      "header": "CPU",
      "key": "cpu",
      "datatype": "kcpu",
      "justification": "right",
      "total": "sum"
    },
    {
      "header": "MEM",
      "key": "memory",
      "datatype": "kmem",
      "justification": "right",
      "total": "sum"
    }
  ]
}
EOF

echo -e "\nTest 1: Short footer - Footer shorter than first column width"
echo "----------------------------------------"
./tables.sh "$layout_file" "$data_file"

# Test 2: Aligned footer - Right side of footer aligns with a column below
cat > "$layout_file" << 'EOF'
{
  "footer": "DO DOKS Pod Name, CPU, and MEM Statistics",
  "theme": "Red",
  "columns": [
    {
      "header": "Pod Name",
      "key": "pod_name",
      "datatype": "text",
      "total": "count",
      "width": 10
    },
    {
      "header": "CPU",
      "key": "cpu",
      "datatype": "kcpu",
      "justification": "right",
      "total": "sum"
    },
    {
      "header": "MEM",
      "key": "memory",
      "datatype": "kmem",
      "justification": "right",
      "total": "sum"
    }
  ]
}
EOF

echo -e "\nTest 2: Aligned footer - Right side of footer aligns with a column below"
echo "----------------------------------------"
./tables.sh "$layout_file" "$data_file"

# Test 3: Perfect Footer - Footer width equals table width
cat > "$layout_file" << 'EOF'
{
  "footer": "DO DOKS Pod Name, CPU, and Memory Statistics Tables",
  "theme": "Red",
  "columns": [
    {
      "header": "Pod Name",
      "key": "pod_name",
      "datatype": "text",
      "total": "count",
      "width": 15
    },
    {
      "header": "CPU",
      "key": "cpu",
      "datatype": "kcpu",
      "justification": "right",
      "total": "sum",
      "width": 8
    },
    {
      "header": "MEM",
      "key": "memory",
      "datatype": "kmem",
      "justification": "right",
      "total": "sum",
      "width": 8
    }
  ]
}
EOF

echo -e "\nTest 3: Perfect Footer - Footer width equals table width"
echo "----------------------------------------"
./tables.sh "$layout_file" "$data_file"

# Test 4: Wide Footer - Footer wider than table width
cat > "$layout_file" << 'EOF'
{
  "footer": "Kubernetes Cluster Pod Resource Utilization Report - Production Environment",
  "theme": "Red",
  "columns": [
    {
      "header": "Pod Name",
      "key": "pod_name",
      "datatype": "text",
      "total": "count",
      "width": 15
    },
    {
      "header": "CPU",
      "key": "cpu",
      "datatype": "kcpu",
      "justification": "right",
      "total": "sum",
      "width": 8
    },
    {
      "header": "MEM",
      "key": "memory",
      "datatype": "kmem",
      "justification": "right",
      "total": "sum",
      "width": 8
    }
  ]
}
EOF

echo -e "\nTest 4: Wide Footer - Footer wider than table width"
echo "----------------------------------------"
./tables.sh "$layout_file" "$data_file"

# Cleanup
rm -f "$layout_file" "$data_file"
