#!/usr/bin/env bash

# Kubernetes Node and Pod Information Script
# Requires: kubectl, jq, tables.sh
# Optional: metrics-server for resource usage
# Version: 1.2.6

# Usage: ./nodeinfo.sh [--debug] [--help]

set -uo pipefail

# Source table library
if [ ! -f "tables.sh" ]; then
    echo -e "\033[0;31mError: tables.sh not found\033[0m" >&2
    exit 1
fi
source tables.sh

# Configuration
VERSION="1.2.6"
DEBUG=false

# Help message
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --debug    Enable debug output
  --help     Show this help message

Description:
  Displays detailed information about Kubernetes nodes and their pods,
  including resource usage if metrics-server is installed.

Requirements:
  - kubectl: For cluster access
  - jq: For JSON processing
  - tables.sh: For table rendering
  - metrics-server: Optional, for resource usage
EOF
    exit 0
}

# Debug logging
debug() {
    if [ "$DEBUG" = true ]; then
        echo -e "${YELLOW}[DEBUG $(date +%H:%M:%S)] $@${NC}" >&2
    fi
}

# Error trap
trap 'echo -e "${RED}Error: Script failed at line $LINENO${NC}"; debug "Last command: $BASH_COMMAND"; exit 1' ERR

# Run command with error handling
run_cmd() {
    local cmd="$1" output_file="$2"
    debug "Executing: $cmd"
    if ! bash -c "$cmd" > "$output_file" 2> >(tee /tmp/cmd_stderr.$$ >&2); then
        echo -e "${RED}Error: Command failed: $cmd${NC}"
        debug "Command stderr:\n$(cat /tmp/cmd_stderr.$$)"
        rm -f /tmp/cmd_stderr.$$
        return 1
    fi
    rm -f /tmp/cmd_stderr.$$
    return 0
}

# Check dependencies
check_dependencies() {
    debug "Checking dependencies"
    local missing=()
    command -v kubectl >/dev/null || missing+=("kubectl")
    command -v jq >/dev/null || missing+=("jq")
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing dependencies: ${missing[*]}${NC}"
        echo "Please install them and try again."
        exit 1
    fi
    debug "Dependencies OK: kubectl, jq"
}

# Check metrics-server availability
check_metrics_server() {
    debug "Checking metrics-server"
    local output_file=$(mktemp)
    if run_cmd "kubectl top nodes" "$output_file"; then
        debug "Metrics-server is available"
        rm -f "$output_file"
        return 0
    fi
    debug "Metrics-server is not available"
    rm -f "$output_file"
    return 1
}

# Normalize resource values to millicores (CPU) or bytes (memory)
normalize_resource() {
    local value="$1" type="$2"
    debug "Normalizing resource: $value ($type)"
    if [ -z "$value" ] || [ "$value" = "N/A" ] || [ "$value" = "0" ]; then
        echo "0"
        return
    fi
    case "$value" in
        *m) echo "${value%m}" ;; # Millicores
        *.[0-9]*) echo "$(awk "BEGIN {print ${value} * 1000}")" ;; # Fractional CPU (e.g., 0.5)
        *[0-9]) echo "$((${value} * 1000))" ;; # Whole CPU (e.g., 1)
        *Ki) echo "$((${value%Ki} * 1024))" ;;
        *Mi) echo "$((${value%Mi} * 1024 * 1024))" ;;
        *Gi) echo "$((${value%Gi} * 1024 * 1024 * 1024))" ;;
        *M) echo "$((${value%M} * 1000000))" ;;
        *G) echo "$((${value%G} * 1000000000))" ;;
        *) echo "0"; debug "Unknown resource format: $value" ;;
    esac
}

# Format resource values for display
format_resource() {
    local value="$1" type="$2"
    if [ -z "$value" ] || [ "$value" -eq 0 ]; then
        echo ""
        return
    fi
    case "$type" in
        cpu) printf "%dm" "$value" ;; # Millicores
        mem)
            if [ "$value" -ge $((1000*1000*1000)) ]; then
                printf "%dG" "$((value / 1000 / 1000 / 1000))"
            elif [ "$value" -ge $((1000*1000)) ]; then
                printf "%dM" "$((value / 1000 / 1000))"
            else
                printf "%dK" "$((value / 1000))"
            fi
            ;;
        *) echo "$value" ;;
    esac
}

# Get pod information for a node
get_node_pods() {
    local node_name="$1" has_metrics="$2"
    local -n usage_data_ref=$3 # Reference to usage_data array
    local json_file=$(mktemp)
    local headers=("POD" "NAMESPACE" "WORKLOAD" "WORKTYPE" "CPU REQ" "CPU LIM" "CPU USE" "MEM REQ" "MEM LIM" "MEM USE" "PORTS")

    echo -e "${BLUE}=== Node: $node_name ===${NC}"
    debug "Starting pod processing for $node_name"

    # Fetch pods
    local pods_file=$(mktemp)
    if ! run_cmd "kubectl get pods -A -o json" "$pods_file"; then
        echo -e "${RED}Error: Failed to fetch pods${NC}"
        rm -f "$json_file" "$pods_file"
        return 1
    fi

    # Filter pods by node
    local node_pods_file=$(mktemp)
    if ! jq "[.items[] | select(.spec.nodeName == \"$node_name\")]" "$pods_file" > "$node_pods_file"; then
        echo -e "${RED}Error: Failed to filter pods for node $node_name${NC}"
        debug "jq filter failed for node $node_name"
        rm -f "$json_file" "$pods_file" "$node_pods_file"
        return 1
    fi

    local pod_count
    pod_count=$(jq '. | length' "$node_pods_file")
    debug "Found $pod_count pods on node $node_name"
    if [ "$pod_count" -eq 0 ]; then
        echo -e "${YELLOW}No pods found on node $node_name${NC}"
        draw_table "$json_file" "${headers[@]}" --separator=namespace --alignments=left,left,left,left,right,right,right,right,right,right,left ${DEBUG:+--debug}
        rm -f "$json_file" "$pods_file" "$node_pods_file"
        return 0
    fi

    # Prepare JSON data
    local processed_pods=0 total_cpu_req=0 total_cpu_lim=0 total_cpu_use=0
    local total_mem_req=0 total_mem_lim=0 total_mem_use=0
    local pod_data=()

    while IFS= read -r pod_json; do
        ((processed_pods++))
        local name namespace workload worktype cpu_req cpu_lim mem_req mem_lim ports
        name=$(echo "$pod_json" | jq -r '.metadata.name // "Unknown"')
        namespace=$(echo "$pod_json" | jq -r '.metadata.namespace // "Unknown"')
        workload=$(echo "$pod_json" | jq -r '.metadata.labels.workload // "Missing"')
        worktype=$(echo "$pod_json" | jq -r '.metadata.labels.worktype // "Missing"')
        cpu_req=$(echo "$pod_json" | jq -r '[.spec.containers[].resources.requests.cpu // "0"] | join(",")')
        cpu_lim=$(echo "$pod_json" | jq -r '[.spec.containers[].resources.limits.cpu // "0"] | join(",")')
        mem_req=$(echo "$pod_json" | jq -r '[.spec.containers[].resources.requests.memory // "0"] | join(",")')
        mem_lim=$(echo "$pod_json" | jq -r '[.spec.containers[].resources.limits.memory // "0"] | join(",")')
        ports=$(echo "$pod_json" | jq -r '[.spec.containers[].ports[]? | "\(.containerPort)/\(.protocol)"] | join(";") // ""')

        debug "Processing pod: $name ($namespace)"
        debug "Raw data: NAME=$name, NS=$namespace, WORKLOAD=$workload, WORKTYPE=$worktype, CPU_REQ=$cpu_req, CPU_LIM=$cpu_lim, MEM_REQ=$mem_req, MEM_LIM=$mem_lim, PORTS=$ports"

        # Normalize resources
        local cpu_req_val=0 cpu_lim_val=0 mem_req_val=0 mem_lim_val=0
        IFS=',' read -ra cpu_req_array <<< "$cpu_req"
        for val in "${cpu_req_array[@]}"; do
            cpu_req_val=$((cpu_req_val + $(normalize_resource "$val" cpu)))
        done
        IFS=',' read -ra cpu_lim_array <<< "$cpu_lim"
        for val in "${cpu_lim_array[@]}"; do
            cpu_lim_val=$((cpu_lim_val + $(normalize_resource "$val" cpu)))
        done
        IFS=',' read -ra mem_req_array <<< "$mem_req"
        for val in "${mem_req_array[@]}"; do
            mem_req_val=$((mem_req_val + $(normalize_resource "$val" mem)))
        done
        IFS=',' read -ra mem_lim_array <<< "$mem_lim"
        for val in "${mem_lim_array[@]}"; do
            mem_lim_val=$((mem_lim_val + $(normalize_resource "$val" mem)))
        done

        # Get usage
        local cpu_use_val=0 mem_use_val=0 cpu_use="" mem_use=""
        if [ "$has_metrics" = true ] && [ ${#usage_data_ref[@]} -gt 0 ]; then
            for usage_line in "${usage_data_ref[@]}"; do
                IFS=' ' read -r usage_ns usage_pod usage_cpu usage_mem _ <<< "$usage_line"
                if [ "$usage_ns" = "$namespace" ] && [ "$usage_pod" = "$name" ]; then
                    cpu_use_val=$(normalize_resource "$usage_cpu" cpu)
                    mem_use_val=$(normalize_resource "$usage_mem" mem)
                    cpu_use=$(format_resource "$cpu_use_val" cpu)
                    mem_use=$(format_resource "$mem_use_val" mem)
                    debug "Found usage for $namespace/$name: CPU=$cpu_use, MEM=$mem_use"
                    break
                fi
            done
        fi

        # Update totals
        total_cpu_req=$((total_cpu_req + cpu_req_val))
        total_cpu_lim=$((total_cpu_lim + cpu_lim_val))
        total_cpu_use=$((total_cpu_use + cpu_use_val))
        total_mem_req=$((total_mem_req + mem_req_val))
        total_mem_lim=$((total_mem_lim + mem_lim_val))
        total_mem_use=$((total_mem_use + mem_use_val))

        # Format for display
        cpu_req=$(format_resource "$cpu_req_val" cpu)
        cpu_lim=$(format_resource "$cpu_lim_val" cpu)
        mem_req=$(format_resource "$mem_req_val" mem)
        mem_lim=$(format_resource "$mem_lim_val" mem)

        debug "Formatted: CPU_REQ=$cpu_req, CPU_LIM=$cpu_lim, CPU_USE=$cpu_use, MEM_REQ=$mem_req, MEM_LIM=$mem_lim, MEM_USE=$mem_use"

        # Add row to JSON data
        local row_json
        row_json=$(jq -n --arg pod "$name" \
                         --arg namespace "$namespace" \
                         --arg workload "$workload" \
                         --arg worktype "$worktype" \
                         --arg cpu_req "$cpu_req" \
                         --arg cpu_lim "$cpu_lim" \
                         --arg cpu_use "$cpu_use" \
                         --arg mem_req "$mem_req" \
                         --arg mem_lim "$mem_lim" \
                         --arg mem_use "$mem_use" \
                         --arg ports "$ports" \
                         '{pod: $pod, namespace: $namespace, workload: $workload, worktype: $worktype, cpu_req: $cpu_req, cpu_lim: $cpu_lim, cpu_use: $cpu_use, mem_req: $mem_req, mem_lim: $mem_lim, mem_use: $mem_use, ports: $ports}')
        pod_data+=("$row_json")
    done < <(jq -c '.[]' "$node_pods_file")

    debug "Processed $processed_pods pods"

    # Write JSON data
    printf '%s\n' "${pod_data[@]}" | jq -s '.' > "$json_file"

    # Add totals row
    local totals_json
    totals_json=$(jq -n --arg pod "Total ($processed_pods pods)" \
                       --arg cpu_req "$(format_resource "$total_cpu_req" cpu)" \
                       --arg cpu_lim "$(format_resource "$total_cpu_lim" cpu)" \
                       --arg cpu_use "$(format_resource "$total_cpu_use" cpu)" \
                       --arg mem_req "$(format_resource "$total_mem_req" mem)" \
                       --arg mem_lim "$(format_resource "$total_mem_lim" mem)" \
                       --arg mem_use "$(format_resource "$total_mem_use" mem)" \
                       '{pod: $pod, namespace: "", workload: "", worktype: "", cpu_req: $cpu_req, cpu_lim: $cpu_lim, cpu_use: $cpu_use, mem_req: $mem_req, mem_lim: $mem_lim, mem_use: $mem_use, ports: ""}')
    jq -s '. + ['"$totals_json"']' "$json_file" > "$json_file.tmp" && mv "$json_file.tmp" "$json_file"

    # Render table
    draw_table "$json_file" "${headers[@]}" --separator=namespace --alignments=left,left,left,left,right,right,right,right,right,right,left ${DEBUG:+--debug}
    rm -f "$json_file" "$pods_file" "$node_pods_file"
}

# Get node information
get_nodes_info() {
    debug "Fetching nodes"
    local nodes_file=$(mktemp)
    local usage_data=()
    if ! run_cmd "kubectl get nodes -o json" "$nodes_file"; then
        echo -e "${RED}Error: Failed to fetch nodes${NC}"
        rm -f "$nodes_file"
        return 1
    fi

    local node_count
    node_count=$(jq '.items | length' "$nodes_file")
    debug "Found $node_count nodes"
    if [ "$node_count" -eq 0 ]; then
        echo -e "${YELLOW}No nodes found in the cluster${NC}"
        rm -f "$nodes_file"
        return 0
    fi

    if [ "$DEBUG" = true ]; then
        debug "Nodes JSON:\n$(cat "$nodes_file" | jq .)"
    fi

    local has_metrics=false
    if check_metrics_server; then
        has_metrics=true
        local usage_file=$(mktemp)
        if run_cmd "kubectl top pods -A --no-headers" "$usage_file"; then
            while IFS= read -r line; do
                [ -n "$line" ] && usage_data+=("$line")
            done < "$usage_file"
            debug "Fetched usage data: ${#usage_data[@]} lines"
            if [ "$DEBUG" = true ] && [ ${#usage_data[@]} -gt 0 ]; then
                debug "Usage data:\n${usage_data[*]}"
            fi
        else
            debug "No usage data available"
        fi
        rm -f "$usage_file"
    fi

    debug "Processing ready nodes"
    local nodes_output
    nodes_output=$(jq -r '.items[] | select(.status.conditions[] | select(.type == "Ready" and .status == "True")) | .metadata.name' "$nodes_file" 2>/tmp/jq_stderr.$$)
    local jq_exit=$?
    if [ $jq_exit -ne 0 ]; then
        echo -e "${RED}Error: Failed to process node data${NC}"
        debug "jq stderr:\n$(cat /tmp/jq_stderr.$$)"
        rm -f "$nodes_file" /tmp/jq_stderr.$$
        return 1
    fi
    rm -f /tmp/jq_stderr.$$

    if [ -z "$nodes_output" ]; then
        echo -e "${YELLOW}No ready nodes found in the cluster${NC}"
        rm -f "$nodes_file"
        return 0
    fi

    echo "$nodes_output" | while IFS= read -r node_name; do
        debug "Processing node: $node_name"
        get_node_pods "$node_name" "$has_metrics" usage_data
    done
    rm -f "$nodes_file"
}

# Main execution
main() {
    debug "Starting script v$VERSION"
    check_dependencies

    echo -e "${BLUE}=== Kubernetes Node and Pod Information (v$VERSION) ===${NC}"
    debug "Checking cluster connectivity"
    local cluster_info_file=$(mktemp)
    if ! run_cmd "kubectl cluster-info" "$cluster_info_file"; then
        echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
        rm -f "$cluster_info_file"
        exit 1
    fi
    rm -f "$cluster_info_file"

    if ! check_metrics_server; then
        echo -e "${YELLOW}Note: metrics-server not available - usage data will be omitted${NC}"
    fi

    get_nodes_info
    echo -e "${GREEN}=== Information Collection Complete ===${NC}"
}

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --debug) DEBUG=true; shift ;;
        --help) show_help ;;
        *) echo -e "${RED}Error: Unknown option: $1${NC}"; show_help ;;
    esac
done

main
