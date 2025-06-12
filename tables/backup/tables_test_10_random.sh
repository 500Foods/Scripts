#!/usr/bin/env bash

# Create temporary files for our JSON
layout_file=$(mktemp)
data_file=$(mktemp)

# Test 1: Title shorter than table width
cat > "$layout_file" << 'EOF'
{
  "title": "Pod Resources",
  "footer": "Data collected from Kubernetes API",
  "theme": "Red",
  "columns": [
    {
      "header": "Namespace",
      "key": "namespace",
      "datatype": "text",
      "break": true
    },
    {
      "header": "Pod Name",
      "key": "pod_name",
      "datatype": "text"
    },
    {
      "header": "CPU",
      "key": "cpu",
      "datatype": "kcpu",
      "justification": "right",
      "total": "sum"
    },
    {
      "header": "Memory",
      "key": "memory",
      "datatype": "kmem",
      "justification": "right",
      "total": "sum"
    }
  ]
}
EOF

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
    "cpu": "250m",
    "memory": "128Mi"
  },
  {
    "namespace": "default",
    "pod_name": "nginx-deployment-66b6c48dd5-efgh2",
    "cpu": "250m",
    "memory": "128Mi"
  }
]
EOF

echo -e "\nTest 1: Title shorter than table width"
echo "----------------------------------------"
./tables.sh "$layout_file" "$data_file"

# Test 2: Title longer than table width
cat > "$layout_file" << 'EOF'
{
  "title": "Kubernetes Pod Resource Utilization Report - Production Cluster",
  "footer": "Production Cluster Status",
  "theme": "Blue",
  "columns": [
    {
      "header": "Pod Name",
      "key": "pod_name",
      "datatype": "text",
      "padding": 1,
      "width": 35
    },
    {
      "header": "CPU Usage",
      "key": "cpu",
      "datatype": "kcpu",
      "justification": "right",
      "padding": 1,
      "width": 10
    }
  ]
}
EOF

cat > "$data_file" << 'EOF'
[
  {
    "pod_name": "coredns-787d4b4b6c-abcd1",
    "cpu": "100m"
  },
  {
    "pod_name": "nginx-deployment-66b6c48dd5-efgh1",
    "cpu": "250m"
  }
]
EOF

echo -e "\nTest 2: Title longer than table width"
echo "----------------------------------------"
./tables.sh "$layout_file" "$data_file"

# Test 3: No title
cat > "$layout_file" << 'EOF'
{
  "theme": "Red",
  "footer": "System Metrics",
  "columns": [
    {
      "header": "Pod",
      "key": "pod_name",
      "datatype": "text"
    },
    {
      "header": "CPU",
      "key": "cpu",
      "datatype": "kcpu",
      "justification": "right"
    }
  ]
}
EOF

echo -e "\nTest 3: No title"
echo "----------------------------------------"
./tables.sh "$layout_file" "$data_file"

# Test 4: Title matching first column width
cat > "$layout_file" << 'EOF'
{
  "title": "Pod Name Column",
  "footer": "Column Examples",
  "theme": "Blue",
  "columns": [
    {
      "header": "Pod Name",
      "key": "pod_name",
      "datatype": "text",
      "padding": 1
    },
    {
      "header": "CPU",
      "key": "cpu",
      "datatype": "kcpu",
      "justification": "right",
      "padding": 1
    }
  ]
}
EOF

echo -e "\nTest 4: Title matching first column width"
echo "----------------------------------------"
./tables.sh "$layout_file" "$data_file"

# Test 5: Title matching exact table width
cat > "$layout_file" << 'EOF'
{
  "title": "Pod Name and CPU Usage Stats",
  "footer": "Generated with tables.sh",
  "theme": "Red",
  "columns": [
    {
      "header": "Pod Name",
      "key": "pod_name",
      "datatype": "text",
      "padding": 1
    },
    {
      "header": "CPU",
      "key": "cpu",
      "datatype": "kcpu",
      "justification": "right",
      "padding": 1
    }
  ]
}
EOF

echo -e "\nTest 5: Title matching exact table width"
echo "----------------------------------------"
./tables.sh "$layout_file" "$data_file"

# Cleanup
rm -f "$layout_file" "$data_file"