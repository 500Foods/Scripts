#!/bin/bash

# node_info.sh - DOKS Node and Pod Information Tool
#
# Version History:
# 2.2.4 - Removed Kubernetes from various places, added DOKS
# 2.2.3 - Added options to select table, quiet mode, and theme
# 2.2.2 - Added Pod Images table 
# 2.2.1 - Fixed RAM extraction and added sums to all resource columns
# 2.2.0 - Added debug mode and fixed RAM values in pod resource usage table
# 2.1.9 - Fixed RAM values in pod resource usage table
# 2.1.8 - Fixed RAM and CPU values in pod resource usage table
# 2.1.7 - Fixed pod resource usage table with proper resource extraction
# 2.1.6 - Enhanced pod resource usage table and fixed NET-U status
# 2.1.5 - Improved pod table with namespace breaks and restarts column
# 2.1.4 - Enhanced Node Resource Usage table with pressure metrics
# 2.1.3 - Using RAM and DISK values from doctl
# 2.1.2 - Added KERNEL column, renamed RAM/DISK columns with units
# 2.1.1 - Adjusted column order and added back CPU/RAM from capacity
# 2.1.0 - Added doctl integration for additional node information
# 2.0.3 - Fixed datatype issues and improved memory calculation
# 2.0.2 - Fixed jq query for tags field and optimized script
# 2.0.1 - Updated table layout for nodes overview with improved formatting
# 2.0.0 - Updated to use tables.sh with JSON layout approach
# 1.2.6 - Previous version with draw_table method
#
# Usage: ./node_info.sh [--debug]

# Configuration
APPVERSION="2.2.4"
DEBUG="false"
QUIET="false"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TABLES_SCRIPT="${SCRIPT_DIR}/../tables/tables.sh"
TEMP_DIR=$(mktemp -d)
TABLE_THEME="Red"
SELECTED_TABLES="ABCDE"  # Default to all tables (A, B, C, D, E)

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h) 
            echo "Usage: ./node_info.sh [options]"
            echo "Options:"
            echo "  --help, -h          Show this help message and exit"
            echo "  --debug, -d         Enable debug mode"
            echo "  --quiet, -q         Suppress non-table output"
            echo "  --theme, -t <theme> Set the theme for tables (default: Red)"
            echo "  --tables, -b <tables> Specify tables to display (e.g., ABD for tables A, B, and D)"
            echo "Tables:"
            echo "  A: Nodes Overview"
            echo "  B: Node Resource Usage"
            echo "  C: Pods on Nodes (per-Node)"
            echo "  D: Pod Resource Usage on Node (per-Node)"
            echo "  E: Pod Images on Node (per-Node)"
            exit 0
            ;;
        --debug|-d) DEBUG="true"; shift ;;
        --quiet|-q) QUIET="true"; shift ;;
        --theme|-t) TABLE_THEME="$2"; shift 2 ;;
        --tables|-b) SELECTED_TABLES="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# If DEBUG is true, print a message unless QUIET is true
if [ "$DEBUG" = "true" ] && [ "$QUIET" != "true" ]; then
    echo "Debug mode enabled"
fi

# Function to print debug messages if DEBUG is true
debug() {
    if [ "$DEBUG" = "true" ]; then
        echo "Debug: $@"
    fi
}

cleanup() {
    debug "Cleaning up temporary files in $TEMP_DIR"
    rm -rf "$TEMP_DIR"
}

# Set up cleanup on exit
trap cleanup EXIT

# Check if tables.sh exists
if [ ! -f "$TABLES_SCRIPT" ]; then
    if [ "$QUIET" != "true" ]; then
        echo "Error: tables.sh not found at $TABLES_SCRIPT"
    fi
    exit 1
fi

# Function to create a table layout JSON file
create_table_layout() {
    local name="$1"
    local columns="$2"
    local file="${TEMP_DIR}/${name}_layout.json"
    echo "$columns" > "$file"
    echo "$file"
}

# Function to create a table data JSON file
create_table_data() {
    local name="$1"
    local data="$2"
    local file="${TEMP_DIR}/${name}_data.json"
    echo "$data" > "$file"
    echo "$file"
}

# Function to render a table using tables.sh
render_table() {
    local name="$1"
    local layout_file="$2"
    local data_file="$3"
    
    debug "Rendering table $name with layout $layout_file and data $data_file"
    
    # Add debug flag if needed
    local debug_flag=""
    [ "$DEBUG" = "true" ] && debug_flag="--debug"
    
    bash "$TABLES_SCRIPT" "$layout_file" "$data_file" $debug_flag
}

# Print script header unless QUIET is true
if [ "$QUIET" != "true" ]; then
    echo "=== Node and Pod Information Tool (v$APPVERSION) ==="
fi

# Function to check metrics-server availability
check_metrics_server() {
    debug "Checking metrics-server availability..."
    if kubectl top nodes >/dev/null 2>&1; then
        debug "Metrics-server is available"
        echo "true"
    else
        debug "Metrics-server is not available"
        echo "false"
    fi
}

# Function to get node information
get_node_info() {
    local metrics_available=$(check_metrics_server)
    debug "Metrics available: $metrics_available"
    
    # Create temporary files
    local nodes_temp="${TEMP_DIR}/nodes_temp.json"
    
    debug "Nodes temp file: $nodes_temp"
    
    # Get node resources
    debug "Fetching all node resources..."
    kubectl get nodes -o json > "$nodes_temp"
    
    # Count total nodes
    local total_nodes=$(jq '.items | length' "$nodes_temp")
    debug "Total nodes found: $total_nodes"
    
    # Create table data JSON for nodes with basic information
    local data
    data=$(jq -s '[.[] | .items[] | {
        name: .metadata.name,
        nodepool: (.metadata.labels["doks.digitalocean.com/node-pool"] // ""),
        version: .status.nodeInfo.kubeletVersion,
        kernel: .status.nodeInfo.kernelVersion,
        internal_ip: ([.status.addresses[] | select(.type == "InternalIP") | .address] | .[0]),
        external_ip: ([.status.addresses[] | select(.type == "ExternalIP") | .address] | .[0] // ""),
        cpu: .status.capacity.cpu
    }]' "$nodes_temp")
    
    # Create a temporary file to store enhanced node data
    local enhanced_data_file="${TEMP_DIR}/enhanced_node_data.json"
    echo "[]" > "$enhanced_data_file"
    
    # Process each node to get additional information from doctl
    echo "$data" | jq -c '.[]' | while read -r node_json; do
        local node_name=$(echo "$node_json" | jq -r '.name')
        debug "Getting additional info for node: $node_name"
        
        # Get doctl information for the node
        local doctl_info
        if doctl_info=$(doctl compute droplet get "$node_name" --format ID,Name,PublicIPv4,PrivateIPv4,Memory,VCPUs,Disk,Region,Status,Tags --no-header 2>/dev/null); then
            debug "doctl info: $doctl_info"
            
            # Parse doctl output
            read -r id name public_ip private_ip memory vcpus disk region status tags <<< "$doctl_info"
            
            # Process tags from doctl
            local filtered_tags=""
            if [[ -n "$tags" ]]; then
                # Split by commas and filter out tags with colons
                IFS=',' read -ra tag_array <<< "$tags"
                for tag in "${tag_array[@]}"; do
                    if [[ "$tag" != *":"* ]]; then
                        filtered_tags+="$tag,"
                    fi
                done
                filtered_tags=${filtered_tags%,}
            fi
            
            # Add RAM, DISK, and tags to node data
            local enhanced_node=$(echo "$node_json" | jq --arg tags "$filtered_tags" --arg ram "$memory" --arg disk "$disk" '. + {tags: $tags, ram_mb: ($ram | tonumber), disk_gb: ($disk | tonumber)}')
            
            # Append to enhanced data file
            jq --argjson node "$enhanced_node" '. += [$node]' "$enhanced_data_file" > "${enhanced_data_file}.tmp" && mv "${enhanced_data_file}.tmp" "$enhanced_data_file"
        else
            # If doctl fails, just use the original node data with empty tags and default RAM/DISK values
            local enhanced_node=$(echo "$node_json" | jq '. + {tags: "", ram_mb: 0, disk_gb: 0}')
            jq --argjson node "$enhanced_node" '. += [$node]' "$enhanced_data_file" > "${enhanced_data_file}.tmp" && mv "${enhanced_data_file}.tmp" "$enhanced_data_file"
            debug "Failed to get doctl info for node: $node_name"
        fi
    done
    
    # Use the enhanced data for the table
    data=$(cat "$enhanced_data_file")
    
    # Create table layout JSON for nodes
    local layout=$(cat <<EOF
{
  "theme": "$TABLE_THEME",
  "title": "A: Nodes Overview",
  "footer": "kubectl get nodes -o json + doctl compute droplet get",
  "footer_position": "right",
  "columns": [
    {
      "header": "NAME",
      "key": "name",
      "datatype": "text",
      "justification": "left",
      "string_limit": 20,
      "summary": "count"
    },
    {
      "header": "NODE-POOL",
      "key": "nodepool",
      "datatype": "text",
      "justification": "left",
      "string_limit": 15
    },
    {
      "header": "VERSION",
      "key": "version",
      "datatype": "text",
      "justification": "left",
      "string_limit": 15
    },
    {
      "header": "KERNEL",
      "key": "kernel",
      "datatype": "text",
      "justification": "left",
      "string_limit": 15
    },
    {
      "header": "INTERNAL-IP",
      "key": "internal_ip",
      "datatype": "text",
      "justification": "left",
      "string_limit": 15
    },
    {
      "header": "EXTERNAL-IP",
      "key": "external_ip",
      "datatype": "text",
      "justification": "left",
      "string_limit": 15
    },
    {
      "header": "CPU",
      "key": "cpu",
      "datatype": "num",
      "justification": "right",
      "string_limit": 5,
      "summary": "sum"
    },
    {
      "header": "RAM-MB",
      "key": "ram_mb",
      "datatype": "num",
      "justification": "right",
      "string_limit": 10,
      "summary": "sum"
    },
    {
      "header": "DISK-GB",
      "key": "disk_gb",
      "datatype": "num",
      "justification": "right",
      "string_limit": 10,
      "summary": "sum"
    },
    {
      "header": "TAGS",
      "key": "tags",
      "datatype": "text",
      "justification": "left",
      "string_limit": 30,
      "wrap_mode": "wrap",
      "wrap_char": ","
    }
  ]
}
EOF
)

    local layout_file=$(create_table_layout "nodes_overview" "$layout")
    local data_file=$(create_table_data "nodes_overview" "$data")
    
    # Check if data was generated successfully
    if [ -s "$data_file" ]; then
        # Render the table only if selected
        if [[ "$SELECTED_TABLES" == *"A"* ]]; then
            render_table "Nodes Overview" "$layout_file" "$data_file"
        elif [ "$QUIET" != "true" ]; then
            echo "Note: Table A (Nodes Overview) omitted per --tables option"
        fi
    else
        if [ "$QUIET" != "true" ]; then
        echo "Error: Failed to generate node data"
    fi
        return 1
    fi
    
    # If metrics are available, display node resource usage
    if [ "$metrics_available" = "true" ]; then
        local metrics_temp="${TEMP_DIR}/nodes_metrics_temp.txt"
        debug "Fetching node metrics..."
        kubectl top nodes --no-headers > "$metrics_temp"
        
        # Create a temporary file to store enhanced metrics data
        local enhanced_metrics_file="${TEMP_DIR}/enhanced_metrics_data.json"
        echo "[]" > "$enhanced_metrics_file"
        
        # Process metrics data and add node pool and pressure metrics
        cat "$metrics_temp" | while read -r line; do
            IFS=' ' read -r name cpu_usage cpu_percent memory_usage memory_percent <<< "$line"
            debug "Processing metrics for node: $name"
            
            # Get node pool from the first table data
            local nodepool=$(echo "$data" | jq -r --arg name "$name" '.[] | select(.name == $name) | .nodepool // ""')
            
            # Get pressure metrics from kubectl get nodes
            local pressure_json
            pressure_json=$(kubectl get node "$name" -o json | jq '.status.conditions[] | select(.type | test("Pressure$"))')
            
            # Extract pressure status values from conditions array
            local net_pressure=$(kubectl get node "$name" -o json | jq -r '.status.conditions[] | select(.type == "NetworkUnavailable") | .status // "Unknown"')
            local pid_pressure=$(echo "$pressure_json" | jq -r 'select(.type == "PIDPressure") | .status // "Unknown"')
            local ram_pressure=$(echo "$pressure_json" | jq -r 'select(.type == "MemoryPressure") | .status // "Unknown"')
            local disk_pressure=$(echo "$pressure_json" | jq -r 'select(.type == "DiskPressure") | .status // "Unknown"')
            
            # Create metrics JSON with additional fields
            local metrics_json=$(cat <<EOF
{
  "name": "$name",
  "nodepool": "$nodepool",
  "cpu": "$cpu_usage",
  "cpu_percent": "$cpu_percent",
  "ram": "$memory_usage",
  "ram_percent": "$memory_percent",
  "net_pressure": "$net_pressure",
  "pid_pressure": "$pid_pressure",
  "ram_pressure": "$ram_pressure",
  "disk_pressure": "$disk_pressure"
}
EOF
)
            
            # Append to enhanced metrics file
            jq --argjson metrics "$metrics_json" '. += [$metrics]' "$enhanced_metrics_file" > "${enhanced_metrics_file}.tmp" && mv "${enhanced_metrics_file}.tmp" "$enhanced_metrics_file"
        done
        
        # Use the enhanced metrics data
        local metrics_data=$(cat "$enhanced_metrics_file")
        
        # Create table layout JSON for node metrics
        local metrics_layout=$(cat <<EOF
{
  "theme": "$TABLE_THEME",
  "title": "B: Node Resource Usage",
  "footer": "kubectl top nodes + kubectl get nodes -o json",
  "footer_position": "right",
  "columns": [
    {
      "header": "NAME",
      "key": "name",
      "datatype": "text",
      "justification": "left",
      "string_limit": 20,
      "summary": "count"
    },
    {
      "header": "NODE-POOL",
      "key": "nodepool",
      "datatype": "text",
      "justification": "left",
      "string_limit": 15
    },
    {
      "header": "CPU",
      "key": "cpu",
      "datatype": "kcpu",
      "justification": "right",
      "string_limit": 10,
      "summary": "sum"
    },
    {
      "header": "CPU %",
      "key": "cpu_percent",
      "datatype": "text",
      "justification": "right",
      "string_limit": 10
    },
    {
      "header": "RAM",
      "key": "ram",
      "datatype": "kmem",
      "justification": "right",
      "string_limit": 15,
      "summary": "sum"
    },
    {
      "header": "RAM %",
      "key": "ram_percent",
      "datatype": "text",
      "justification": "right",
      "string_limit": 10
    },
    {
      "header": "NET-U",
      "key": "net_pressure",
      "datatype": "text",
      "justification": "center",
      "string_limit": 7
    },
    {
      "header": "PID-P",
      "key": "pid_pressure",
      "datatype": "text",
      "justification": "center",
      "string_limit": 7
    },
    {
      "header": "RAM-P",
      "key": "ram_pressure",
      "datatype": "text",
      "justification": "center",
      "string_limit": 7
    },
    {
      "header": "DISK-P",
      "key": "disk_pressure",
      "datatype": "text",
      "justification": "center",
      "string_limit": 7
    }
  ]
}
EOF
)
        
        # Create layout and data files for metrics
        local metrics_layout_file=$(create_table_layout "nodes_metrics" "$metrics_layout")
        local metrics_data_file=$(create_table_data "nodes_metrics" "$metrics_data")
        
        # Check if metrics data was generated successfully
        if [ -s "$metrics_data_file" ]; then
            # Render the metrics table only if selected
            if [[ "$SELECTED_TABLES" == *"B"* ]]; then
                render_table "Node Resource Usage" "$metrics_layout_file" "$metrics_data_file"
            elif [ "$QUIET" != "true" ]; then
                echo "Note: Table B (Node Resource Usage) omitted per --tables option"
            fi
        else
            if [ "$QUIET" != "true" ]; then
            echo "Note: No resource usage data available"
        fi
        fi
    else
        if [ "$QUIET" != "true" ]; then
        echo "Note: metrics-server not available - node resource usage data omitted"
    fi
    fi
    
    return 0
}

# Function to get pod information for each node
get_node_pods_info() {
    local metrics_available=$(check_metrics_server)
    debug "Metrics available for pods: $metrics_available"
    
    # Create temporary files
    local nodes_temp="${TEMP_DIR}/nodes_temp.json"
    local pods_temp="${TEMP_DIR}/pods_temp.json"
    
    debug "Nodes temp file: $nodes_temp"
    debug "Pods temp file: $pods_temp"
    
    # Get node resources
    debug "Fetching all node resources for pod mapping..."
    kubectl get nodes -o json > "$nodes_temp"
    
    # Get all pods
    debug "Fetching all pod resources..."
    kubectl get pods -A -o json > "$pods_temp"
    
    # Count total nodes
    local total_nodes=$(jq '.items | length' "$nodes_temp")
    debug "Total nodes for pod mapping: $total_nodes"
    
    # Process each node
    jq -r '.items[].metadata.name' "$nodes_temp" | while read -r node_name; do
        debug "Processing pods for node: $node_name"
        
        # Create a temporary jq filter file
        local jq_filter="${TEMP_DIR}/pod_filter.jq"
        cat > "$jq_filter" << 'EOF'
[
  .[] | .items[] | 
  select(.spec.nodeName == $node_name) | 
  {
    "pod": .metadata.name,
    "namespace": .metadata.namespace,
    "workload": (.metadata.labels.workload // "Missing"),
    "worktype": (.metadata.labels.worktype // "Missing"),
    "status": .status.phase,
    "age": ((now - (.status.startTime // .metadata.creationTimestamp | fromdateiso8601)) / 86400 | floor | tostring + " days"),
    "restarts": (
      [.status.containerStatuses[]?.restartCount // 0] | add
    )
  }
]
EOF
        
        # Filter pods by node using the filter file
        local node_pods_data
        node_pods_data=$(jq -s --arg node_name "$node_name" -f "$jq_filter" "$pods_temp")
        
        # Check if there are pods on this node
        local pod_count=$(echo "$node_pods_data" | jq 'length')
        debug "Found $pod_count pods on node $node_name"
        
        # Create table layout JSON for pods on this node
        local layout=$(cat <<EOF
{
  "theme": "$TABLE_THEME",
  "title": "C: Pods on Node $node_name",
  "footer": "kubectl get pods -A -o json",
  "footer_position": "right",
  "columns": [
    {
      "header": "POD",
      "key": "pod",
      "datatype": "text",
      "justification": "left",
      "string_limit": 30,
      "summary": "count"
    },
    {
      "header": "NAMESPACE",
      "key": "namespace",
      "datatype": "text",
      "justification": "left",
      "string_limit": 15,
      "break": true
    },
    {
      "header": "WORKLOAD",
      "key": "workload",
      "datatype": "text",
      "justification": "left",
      "string_limit": 10
    },
    {
      "header": "WORKTYPE",
      "key": "worktype",
      "datatype": "text",
      "justification": "left",
      "string_limit": 10
    },
    {
      "header": "STATUS",
      "key": "status",
      "datatype": "text",
      "justification": "left",
      "string_limit": 10
    },
    {
      "header": "AGE",
      "key": "age",
      "datatype": "text",
      "justification": "left",
      "string_limit": 10
    },
    {
      "header": "RESTARTS",
      "key": "restarts",
      "datatype": "num",
      "justification": "right",
      "string_limit": 10
    }
  ]
}
EOF
)
        
        # Create layout and data files
        local layout_file=$(create_table_layout "pods_node_$node_name" "$layout")
        local data_file=$(create_table_data "pods_node_$node_name" "$node_pods_data")
        
        # Check if pod data was generated successfully
        if [ -s "$data_file" ]; then
            # Render the table only if selected
            if [[ "$SELECTED_TABLES" == *"C"* ]]; then
                render_table "Pods on Node $node_name" "$layout_file" "$data_file"
            elif [ "$QUIET" != "true" ]; then
                echo "Note: Table C (Pods on Node $node_name) omitted per --tables option"
            fi
        else
            if [ "$QUIET" != "true" ]; then
        echo "Note: No pods found on node $node_name"
    fi
        fi
        
        # If metrics are available, display pod resource usage for this node
        if [ "$metrics_available" = "true" ]; then
            local pod_metrics_temp="${TEMP_DIR}/pod_metrics_temp_$node_name.txt"
            debug "Fetching pod metrics for node $node_name..."
            kubectl top pods -A --no-headers > "$pod_metrics_temp"
            
            # Fetch pod metrics for all pods
            local pod_metrics_temp="${TEMP_DIR}/pod_metrics_temp.txt"
            debug "Fetching pod metrics for all pods..."
            kubectl top pods -A --no-headers > "$pod_metrics_temp"
            
            # If debug is enabled, show the contents of the pod metrics file
            if [ "$DEBUG" = "true" ]; then
                echo "Pod metrics from kubectl top pods -A:"
                cat "$pod_metrics_temp"
                echo ""
            fi
            
            # Create a temporary file to store pod resource data
            local pod_resources_file="${TEMP_DIR}/pod_resources_data.json"
            echo "[]" > "$pod_resources_file"
            
            # Process each pod on this node
            echo "$node_pods_data" | jq -c '.[]' | while read -r pod_json; do
                local pod_name=$(echo "$pod_json" | jq -r '.pod')
                local pod_namespace=$(echo "$pod_json" | jq -r '.namespace')
                local pod_workload=$(echo "$pod_json" | jq -r '.workload')
                local pod_worktype=$(echo "$pod_json" | jq -r '.worktype')
                
                debug "Processing resource usage for pod: $pod_namespace/$pod_name"
                
                # Get current usage from metrics
                local cpu_act="0"
                local ram_act="0"
                if [ -f "$pod_metrics_temp" ]; then
                    local metrics_line=$(grep -E "^$pod_namespace[[:space:]]+$pod_name[[:space:]]" "$pod_metrics_temp")
                    if [ -n "$metrics_line" ]; then
        debug "Found metrics for pod: $pod_namespace/$pod_name"
        # Use awk to extract CPU and RAM values more reliably
        cpu_act=$(echo "$metrics_line" | awk '{print $3}')
        ram_act=$(echo "$metrics_line" | awk '{print $4}')
        debug "Raw metrics: CPU=$cpu_act, RAM=$ram_act"
                        
                        # Process CPU value (convert from millicores if needed)
                        if [[ "$cpu_act" =~ ([0-9]+)m ]]; then
                            # Convert millicores to cores
                            cpu_act="${BASH_REMATCH[1]}"
                            cpu_act=$(echo "scale=3; $cpu_act / 1000" | bc)
                            debug "Converted CPU from millicores: $cpu_act"
                        else
                            # Remove any non-numeric characters
                            cpu_act=$(echo "$cpu_act" | sed 's/[^0-9.]//g')
                            debug "Cleaned CPU value: $cpu_act"
                        fi
                        
                        # Process RAM value (convert to Mi)
                        if [[ "$ram_act" =~ ([0-9]+)Mi ]]; then
                            # Already in Mi
                            ram_act="${BASH_REMATCH[1]}"
                            debug "RAM already in Mi: $ram_act"
                        elif [[ "$ram_act" =~ ([0-9]+)Gi ]]; then
                            # Convert Gi to Mi
                            ram_act="${BASH_REMATCH[1]}"
                            ram_act=$(echo "scale=0; $ram_act * 1024" | bc)
                            debug "Converted RAM from Gi to Mi: $ram_act"
                        elif [[ "$ram_act" =~ ([0-9]+)Ki ]]; then
                            # Convert Ki to Mi
                            ram_act="${BASH_REMATCH[1]}"
                            ram_act=$(echo "scale=0; $ram_act / 1024" | bc)
                            debug "Converted RAM from Ki to Mi: $ram_act"
                        else
                            # Try to extract numeric value
                            ram_act=$(echo "$ram_act" | grep -o '[0-9]\+')
                            debug "Extracted numeric RAM value: $ram_act"
                            if [ -z "$ram_act" ]; then
                                ram_act="0"
                                debug "No numeric RAM value found, defaulting to 0"
                            fi
                        fi
                        
                        debug "Processed metrics for pod $pod_namespace/$pod_name: CPU=$cpu_act, RAM=$ram_act"
                    fi
                fi
                
                # Get pod resource requests and limits
                debug "Getting resource requests and limits for pod: $pod_namespace/$pod_name"
                local cpu_req="0"
                local cpu_lim="0"
                local ram_req="0"
                local ram_lim="0"
                
                # Use the existing pods data instead of making another API call
                debug "Extracting resources from existing pods data for $pod_namespace/$pod_name"
                local pod_resources
                pod_resources=$(jq -r --arg ns "$pod_namespace" --arg name "$pod_name" '.items[] | select(.metadata.namespace == $ns and .metadata.name == $name) | .spec.containers[].resources' "$pods_temp")
                
                if [ -n "$pod_resources" ]; then
                    debug "Pod resources JSON: $pod_resources"
                    
                    # Extract CPU requests directly
                    local cpu_requests
                    cpu_requests=$(echo "$pod_resources" | jq -r '.requests.cpu // "0"' 2>/dev/null)
                    debug "CPU requests: $cpu_requests"
                    
                    # Process each CPU request
                    for req in $cpu_requests; do
                        debug "Processing CPU request: $req"
                        if [[ "$req" =~ ([0-9]+)m ]]; then
                            # Convert millicores to cores
                            local val="${BASH_REMATCH[1]}"
                            val=$(echo "scale=3; $val / 1000" | bc)
                            cpu_req=$(echo "scale=3; $cpu_req + $val" | bc)
                            debug "Added $val cores to CPU request, total now: $cpu_req"
                        elif [[ "$req" =~ ^[0-9.]+$ ]]; then
                            # Already in cores
                            cpu_req=$(echo "scale=3; $cpu_req + $req" | bc)
                            debug "Added $req cores to CPU request, total now: $cpu_req"
                        fi
                    done
                    
                    # Extract CPU limits directly
                    local cpu_limits
                    cpu_limits=$(echo "$pod_resources" | jq -r '.limits.cpu // "0"' 2>/dev/null)
                    debug "CPU limits: $cpu_limits"
                    
                    # Process each CPU limit
                    for lim in $cpu_limits; do
                        debug "Processing CPU limit: $lim"
                        if [[ "$lim" =~ ([0-9]+)m ]]; then
                            # Convert millicores to cores
                            local val="${BASH_REMATCH[1]}"
                            val=$(echo "scale=3; $val / 1000" | bc)
                            cpu_lim=$(echo "scale=3; $cpu_lim + $val" | bc)
                            debug "Added $val cores to CPU limit, total now: $cpu_lim"
                        elif [[ "$lim" =~ ^[0-9.]+$ ]]; then
                            # Already in cores
                            cpu_lim=$(echo "scale=3; $cpu_lim + $lim" | bc)
                            debug "Added $lim cores to CPU limit, total now: $cpu_lim"
                        fi
                    done
                    
                    # Extract RAM requests directly
                    local ram_requests
                    ram_requests=$(echo "$pod_resources" | jq -r '.requests.memory // "0"' 2>/dev/null)
                    debug "RAM requests: $ram_requests"
                    
                    # Process each RAM request
                    for req in $ram_requests; do
                        debug "Processing RAM request: $req"
                        if [[ "$req" =~ ([0-9]+)Mi ]]; then
                            # Already in Mi
                            ram_req=$(echo "scale=0; $ram_req + ${BASH_REMATCH[1]}" | bc)
                            debug "Added ${BASH_REMATCH[1]} Mi to RAM request, total now: $ram_req"
                        elif [[ "$req" =~ ([0-9]+)Gi ]]; then
                            # Convert Gi to Mi
                            local val=$(echo "scale=0; ${BASH_REMATCH[1]} * 1024" | bc)
                            ram_req=$(echo "scale=0; $ram_req + $val" | bc)
                            debug "Added $val Mi (from ${BASH_REMATCH[1]} Gi) to RAM request, total now: $ram_req"
                        elif [[ "$req" =~ ([0-9]+)Ki ]]; then
                            # Convert Ki to Mi
                            local val=$(echo "scale=0; ${BASH_REMATCH[1]} / 1024" | bc)
                            ram_req=$(echo "scale=0; $ram_req + $val" | bc)
                            debug "Added $val Mi (from ${BASH_REMATCH[1]} Ki) to RAM request, total now: $ram_req"
                        elif [[ "$req" =~ ^[0-9]+$ ]]; then
                            # Assume bytes, convert to Mi
                            local val=$(echo "scale=0; $req / (1024 * 1024)" | bc)
                            ram_req=$(echo "scale=0; $ram_req + $val" | bc)
                            debug "Added $val Mi (from $req bytes) to RAM request, total now: $ram_req"
                        fi
                    done
                    
                    # Extract RAM limits directly
                    local ram_limits
                    ram_limits=$(echo "$pod_resources" | jq -r '.limits.memory // "0"' 2>/dev/null)
                    debug "RAM limits: $ram_limits"
                    
                    # Process each RAM limit
                    for lim in $ram_limits; do
                        debug "Processing RAM limit: $lim"
                        if [[ "$lim" =~ ([0-9]+)Mi ]]; then
                            # Already in Mi
                            ram_lim=$(echo "scale=0; $ram_lim + ${BASH_REMATCH[1]}" | bc)
                            debug "Added ${BASH_REMATCH[1]} Mi to RAM limit, total now: $ram_lim"
                        elif [[ "$lim" =~ ([0-9]+)Gi ]]; then
                            # Convert Gi to Mi
                            local val=$(echo "scale=0; ${BASH_REMATCH[1]} * 1024" | bc)
                            ram_lim=$(echo "scale=0; $ram_lim + $val" | bc)
                            debug "Added $val Mi (from ${BASH_REMATCH[1]} Gi) to RAM limit, total now: $ram_lim"
                        elif [[ "$lim" =~ ([0-9]+)Ki ]]; then
                            # Convert Ki to Mi
                            local val=$(echo "scale=0; ${BASH_REMATCH[1]} / 1024" | bc)
                            ram_lim=$(echo "scale=0; $ram_lim + $val" | bc)
                            debug "Added $val Mi (from ${BASH_REMATCH[1]} Ki) to RAM limit, total now: $ram_lim"
                        elif [[ "$lim" =~ ^[0-9]+$ ]]; then
                            # Assume bytes, convert to Mi
                            local val=$(echo "scale=0; $lim / (1024 * 1024)" | bc)
                            ram_lim=$(echo "scale=0; $ram_lim + $val" | bc)
                            debug "Added $val Mi (from $lim bytes) to RAM limit, total now: $ram_lim"
                        fi
                    done
                    
                    debug "Final resource values for pod $pod_namespace/$pod_name: CPU_REQ=$cpu_req, CPU_LIM=$cpu_lim, RAM_REQ=$ram_req, RAM_LIM=$ram_lim"
                fi
                
                # Convert CPU values from cores to millicores with 'm' suffix
                local cpu_req_m=$(echo "$cpu_req * 1000" | bc | sed 's/\..*$//')m
                local cpu_lim_m=$(echo "$cpu_lim * 1000" | bc | sed 's/\..*$//')m
                local cpu_act_m=$(echo "$cpu_act * 1000" | bc | sed 's/\..*$//')m
                
                # Format RAM values with 'Mi' suffix
                local ram_req_mi="${ram_req}Mi"
                local ram_lim_mi="${ram_lim}Mi"
                local ram_act_mi="${ram_act}Mi"
                
                # Create resource JSON with properly formatted values for tables.sh
                local resource_json=$(cat <<EOF
{
  "pod": "$pod_name",
  "namespace": "$pod_namespace",
  "workload": "$pod_workload",
  "worktype": "$pod_worktype",
  "cpu_req": "$cpu_req_m",
  "cpu_lim": "$cpu_lim_m",
  "cpu_act": "$cpu_act_m",
  "ram_req": "$ram_req_mi",
  "ram_lim": "$ram_lim_mi",
  "ram_act": "$ram_act_mi"
}
EOF
)
                debug "Resource JSON for pod $pod_namespace/$pod_name: $resource_json"
                
                # Append to pod resources file
                jq --argjson res "$resource_json" '. += [$res]' "$pod_resources_file" > "${pod_resources_file}.tmp" && mv "${pod_resources_file}.tmp" "$pod_resources_file"
            done
            
            # Use the pod resources data
            local metrics_data=$(cat "$pod_resources_file")
            
            # Create table layout JSON for pod metrics on this node
            local metrics_layout=$(cat <<EOF
{
  "theme": "$TABLE_THEME",
  "title": "D: Pod Resource Usage on Node $node_name",
  "footer": "kubectl top pods -A + kubectl get pod -o json",
  "footer_position": "right",
  "columns": [
    {
      "header": "POD",
      "key": "pod",
      "datatype": "text",
      "justification": "left",
      "string_limit": 30,
      "summary": "count"
    },
    {
      "header": "NAMESPACE",
      "key": "namespace",
      "datatype": "text",
      "justification": "left",
      "string_limit": 15,
      "break": true
    },
    {
      "header": "WORKLOAD",
      "key": "workload",
      "datatype": "text",
      "justification": "left",
      "string_limit": 10
    },
    {
      "header": "WORKTYPE",
      "key": "worktype",
      "datatype": "text",
      "justification": "left",
      "string_limit": 10
    },
    {
      "header": "CPU-R",
      "key": "cpu_req",
      "datatype": "kcpu",
      "justification": "right",
      "summary": "sum"
    },
    {
      "header": "CPU-L",
      "key": "cpu_lim",
      "datatype": "kcpu",
      "justification": "right",
      "summary": "sum"
    },
    {
      "header": "CPU-A",
      "key": "cpu_act",
      "datatype": "kcpu",
      "justification": "right",
      "summary": "sum"
    },
    {
      "header": "RAM-R",
      "key": "ram_req",
      "datatype": "kmem",
      "justification": "right",
      "summary": "sum"
    },
    {
      "header": "RAM-L",
      "key": "ram_lim",
      "datatype": "kmem",
      "justification": "right",
      "summary": "sum"
    },
    {
      "header": "RAM-A",
      "key": "ram_act",
      "datatype": "kmem",
      "justification": "right",
      "summary": "sum"
    }
  ]
}
EOF
)
            
            # Create layout and data files for pod metrics
            local metrics_layout_file=$(create_table_layout "pod_metrics_node_$node_name" "$metrics_layout")
            local metrics_data_file=$(create_table_data "pod_metrics_node_$node_name" "$metrics_data")
            
            # Save debug copies of the JSON files only when debug mode is enabled
            if [ "$DEBUG" = "true" ]; then
                cp "$metrics_layout_file" "./pod_metrics_layout_${node_name}.json"
                cp "$metrics_data_file" "./pod_metrics_data_${node_name}.json"
                echo "DEBUG: Saved layout and data JSON files to current directory"
                echo "DEBUG: Layout file: ./pod_metrics_layout_${node_name}.json"
                echo "DEBUG: Data file: ./pod_metrics_data_${node_name}.json"
                
                # Print sample of the data for debugging
                echo "DEBUG: Sample of pod metrics data (first 2 entries):"
                echo "$metrics_data" | jq 'if length > 0 then .[0:2] else [] end'
                
                # Print the full layout for debugging
                echo "DEBUG: Table layout:"
                cat "$metrics_layout_file"
            fi
            
            # Render the pod metrics table if there is data
            if [ -s "$metrics_data_file" ] && [ "$(echo "$metrics_data" | jq 'length')" -gt 0 ]; then
                if [[ "$SELECTED_TABLES" == *"D"* ]]; then
                    render_table "Pod Resource Usage on Node $node_name" "$metrics_layout_file" "$metrics_data_file"
                elif [ "$QUIET" != "true" ]; then
                    echo "Note: Table D (Pod Resource Usage on Node $node_name) omitted per --tables option"
                fi
            else
                if [ "$QUIET" != "true" ]; then
            echo "Note: No resource usage data available for pods on node $node_name"
        fi
            fi
            
            # Create a temporary file to store pod images data
            local pod_images_file="${TEMP_DIR}/pod_images_data.json"
            echo "[]" > "$pod_images_file"
            
            # Process each pod on this node to extract image information
            echo "$node_pods_data" | jq -c '.[]' | while read -r pod_json; do
                local pod_name=$(echo "$pod_json" | jq -r '.pod')
                local pod_namespace=$(echo "$pod_json" | jq -r '.namespace')
                local pod_workload=$(echo "$pod_json" | jq -r '.workload')
                local pod_worktype=$(echo "$pod_json" | jq -r '.worktype')
                
                debug "Processing images for pod: $pod_namespace/$pod_name"
                
                # Extract images for the pod using jq to join with commas
                local images=""
                images=$(jq -r --arg ns "$pod_namespace" --arg name "$pod_name" '.items[] | select(.metadata.namespace == $ns and .metadata.name == $name) | [.spec.containers[].image] | join(", ")' "$pods_temp")
                
                # Remove SHA hash part (anything from '@' onwards) from each image string
                images=$(echo "$images" | sed 's/@[^,]*//g')
                
                if [ -z "$images" ]; then
                    images="No images found"
                fi
                
                # Create image JSON for the table
                local image_json=$(cat <<EOF
{
  "pod": "$pod_name",
  "namespace": "$pod_namespace",
  "workload": "$pod_workload",
  "worktype": "$pod_worktype",
  "images": "$images"
}
EOF
)
                debug "Image JSON for pod $pod_namespace/$pod_name: $image_json"
                
                # Append to pod images file
                jq --argjson img "$image_json" '. += [$img]' "$pod_images_file" > "${pod_images_file}.tmp" && mv "${pod_images_file}.tmp" "$pod_images_file"
            done
            
            # Use the pod images data
            local images_data=$(cat "$pod_images_file")
            
            # Create table layout JSON for pod images on this node
            local images_layout=$(cat <<EOF
{
  "theme": "$TABLE_THEME",
  "title": "E: Pod Images on Node $node_name",
  "footer": "kubectl get pods -A -o json",
  "footer_position": "right",
  "columns": [
    {
      "header": "POD",
      "key": "pod",
      "datatype": "text",
      "justification": "left",
      "string_limit": 30,
      "summary": "count"
    },
    {
      "header": "NAMESPACE",
      "key": "namespace",
      "datatype": "text",
      "justification": "left",
      "string_limit": 15,
      "break": true
    },
    {
      "header": "WORKLOAD",
      "key": "workload",
      "datatype": "text",
      "justification": "left",
      "string_limit": 10
    },
    {
      "header": "WORKTYPE",
      "key": "worktype",
      "datatype": "text",
      "justification": "left",
      "string_limit": 10
    },
    {
      "header": "IMAGES",
      "key": "images",
      "datatype": "text",
      "justification": "left",
      "string_limit": 50,
      "wrap_mode": "wrap",
      "wrap_char": ","
    }
  ]
}
EOF
)
            
            # Create layout and data files for pod images
            local images_layout_file=$(create_table_layout "pod_images_node_$node_name" "$images_layout")
            local images_data_file=$(create_table_data "pod_images_node_$node_name" "$images_data")
            
            # Render the pod images table if there is data
            if [ -s "$images_data_file" ] && [ "$(echo "$images_data" | jq 'length')" -gt 0 ]; then
                if [[ "$SELECTED_TABLES" == *"E"* ]]; then
                    render_table "Pod Images on Node $node_name" "$images_layout_file" "$images_data_file"
                elif [ "$QUIET" != "true" ]; then
                    echo "Note: Table E (Pod Images on Node $node_name) omitted per --tables option"
                fi
            else
                if [ "$QUIET" != "true" ]; then
        echo "Note: No image data available for pods on node $node_name"
    fi
            fi
        else
            if [ "$QUIET" != "true" ]; then
        echo "Note: metrics-server not available - pod resource usage data for node $node_name omitted"
    fi
        fi
    done
    
    return 0
}

# Main function
main() {
    # Run the individual checks
    get_node_info
    get_node_pods_info
    
    if [ "$QUIET" != "true" ]; then
        echo "=== Audit Complete (v$APPVERSION) ==="
    fi
}

# Run the main function
main
