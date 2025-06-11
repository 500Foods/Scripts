#!/bin/bash

# domain_info.sh - DOKS Ingress and Certificate Manager Audit Tool
# Version: 1.0.0
#
# Version History:
# 1.0.0 - Initial version with tables.sh integration
#
# This script replaces dommgmt.sh with a cleaner implementation that uses tables.sh
# for table rendering.
#
# Usage: ./domain_info.sh [--debug]

# Configuration
VERSION="1.0.0"
INGRESS_CLASS=${INGRESS_CLASS:-"nginx"}
CERT_MANAGER_NAMESPACE=${CERT_MANAGER_NAMESPACE:-"cert-manager"}
INGRESS_NAMESPACE=${INGRESS_NAMESPACE:-"ingress-nginx"}
DEBUG="false"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TABLES_SCRIPT="${SCRIPT_DIR}/../tables/tables.sh"
TEMP_DIR=$(mktemp -d)

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --debug) DEBUG="true"; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

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
    echo "Error: tables.sh not found at $TABLES_SCRIPT"
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

# Print script header
echo "=== DOKS Ingress and Certificate Manager Audit (v$VERSION) ==="
echo "Ingress Class: $INGRESS_CLASS"
echo "Cert-Manager Namespace: $CERT_MANAGER_NAMESPACE"
echo "Ingress Namespace: $INGRESS_NAMESPACE"

# Function to get ingress domains and their backends
get_ingress_domains() {
    echo "=== Ingress Controller Domains ==="
    
    # Create temporary files
    local ingress_temp="${TEMP_DIR}/ingress_temp.json"
    local domains_temp="${TEMP_DIR}/domains_temp.json"
    
    debug "Ingress temp file: $ingress_temp"
    debug "Domains temp file: $domains_temp"
    
    # Get ingress resources
    debug "Fetching all ingress resources..."
    kubectl get ingress -A -o json > "$ingress_temp"
    
    # Count total ingress resources
    local total_ingress=$(jq '.items | length' "$ingress_temp")
    debug "Total ingress resources found: $total_ingress"
    
    # Find all unique ingress classes
    local ingress_classes=$(jq -r '.items[].spec.ingressClassName' "$ingress_temp" | sort | uniq | grep -v "^null$")
    if [ -z "$ingress_classes" ]; then
        ingress_classes=$(jq -r '.items[].metadata.annotations."kubernetes.io/ingress.class"' "$ingress_temp" | sort | uniq | grep -v "^null$")
    fi
    debug "Found ingress classes:"
    echo "$ingress_classes" | while read -r class; do
        if [ -n "$class" ]; then
            debug "  - $class"
        fi
    done
    
    # Create JSON for the ingress domains
    jq -r '.items[] | 
        select((.spec.ingressClassName == "'$INGRESS_CLASS'" or .metadata.annotations."kubernetes.io/ingress.class" == "'$INGRESS_CLASS'") or (("'$ingress_classes'" == "") and (.spec.ingressClassName == null and .metadata.annotations."kubernetes.io/ingress.class" == null))) |
        .metadata.namespace as $namespace |
        .metadata.name as $name |
        .metadata.labels.workload as $workload |
        .metadata.labels.worktype as $worktype |
        (.spec.tls // []) as $tls |
        (.spec.rules // [])[] |
        .host as $host |
        (.http.paths // [])[] |
        {
            namespace: $namespace,
            ingress: $name,
            host: ($host // "(default)"),
            path: (.path // "/"),
            service: (.backend.service.name),
            port: (.backend.service.port.number),
            has_tls: ([$tls[]?.hosts[]? | select(. == ($host // ""))] | length > 0),
            workload: ($workload // "Missing"),
            worktype: ($worktype // "Missing")
        }' "$ingress_temp" > "$domains_temp"
    
    # Store domains for mismatches check
    grep -v "(default)" "$domains_temp" | jq -r '.host' | sort -u > "${TEMP_DIR}/domains.txt"
    
    # Store service info for workloads section
    jq -r '"\(.namespace)\t\(.service)"' "$domains_temp" | sort -u > "${TEMP_DIR}/service_info.txt"
    
    # Create table layout JSON
    local layout=$(cat <<EOF
{
  "theme": "Blue",
  "columns": [
    {
      "header": "DOMAIN",
      "key": "domain",
      "datatype": "text",
      "justification": "left",
      "string_limit": 25
    },
    {
      "header": "NAMESPACE",
      "key": "namespace",
      "datatype": "text",
      "justification": "left",
      "string_limit": 14
    },
    {
      "header": "WORKLOAD",
      "key": "workload",
      "datatype": "text",
      "justification": "left",
      "string_limit": 8
    },
    {
      "header": "WORKTYPE",
      "key": "worktype",
      "datatype": "text",
      "justification": "left",
      "string_limit": 8
    },
    {
      "header": "INGRESS",
      "key": "ingress",
      "datatype": "text",
      "justification": "left",
      "string_limit": 15
    },
    {
      "header": "SERVICE:PORT",
      "key": "service_port",
      "datatype": "text",
      "justification": "left",
      "string_limit": 18
    },
    {
      "header": "PATH",
      "key": "path",
      "datatype": "text",
      "justification": "left",
      "string_limit": 4
    },
    {
      "header": "TLS",
      "key": "tls",
      "datatype": "text",
      "justification": "left",
      "string_limit": 3
    }
  ]
}
EOF
)
    
    # Create table data JSON
    local data=$(jq -s '[.[] | {
        domain: .host,
        namespace: .namespace,
        workload: .workload,
        worktype: .worktype,
        ingress: .ingress,
        service_port: (.service + ":" + (.port | tostring)),
        path: .path,
        tls: (if .has_tls then "YES" else "NO" end)
    }]' "$domains_temp")
    
    # Create layout and data files
    local layout_file=$(create_table_layout "ingress_domains" "$layout")
    local data_file=$(create_table_data "ingress_domains" "$data")
    
    # Render the table
    render_table "Ingress Controller Domains" "$layout_file" "$data_file"
    
    # Save ingress domains for mismatch check
    jq -r 'select(.domain != "(default)") | .domain' "$data_file" | sort -u > "${TEMP_DIR}/ingress_domains.txt"
    
    return 0
}

# Function to get application workloads
get_application_workloads() {
    echo "=== Application Workloads ==="
    
    local service_info_file="${TEMP_DIR}/service_info.txt"
    
    if [ ! -f "$service_info_file" ]; then
        debug "No service info file found or empty result from get_ingress_domains"
        echo "No ingress resources found to process workloads"
        return 1
    fi
    
    debug "Found service info file, processing workloads"
    
    # Create a temporary file for the data
    local data_file="${TEMP_DIR}/workloads_data.json"
    echo "[]" > "$data_file"
    
    # Process each service and namespace
    while IFS=$'\t' read -r namespace service; do
        if [ -z "$namespace" ] || [ -z "$service" ]; then
            continue
        fi
        
        debug "Processing service: $service in namespace: $namespace"
        
        # Get service selector
        local selector=$(kubectl get service "$service" -n "$namespace" -o jsonpath='{.spec.selector}' 2>/dev/null)
        if [ -z "$selector" ]; then
            echo "Service $service in namespace $namespace not found or has no selector"
            continue
        fi
        
        # Convert selector to kubectl label selector format
        local selector_labels=""
        for key in $(echo "$selector" | jq -r 'keys[]'); do
            local value=$(echo "$selector" | jq -r --arg key "$key" '.[$key]')
            if [ -n "$selector_labels" ]; then
                selector_labels="$selector_labels,"
            fi
            selector_labels="${selector_labels}${key}=${value}"
        done
        
        debug "Found selector: $selector_labels"
        
        # Get pods matching the selector
        local pod_json=$(kubectl get pods -n "$namespace" -l "$selector_labels" -o json 2>/dev/null)
        
        # Process each pod
        echo "$pod_json" | jq -r --arg service "$service" --arg namespace "$namespace" '.items[] | 
            (.metadata.name) as $name |
            (.metadata.labels.workload // "Missing") as $workload |
            (.metadata.labels.worktype // "Missing") as $worktype |
            (.status.phase) as $phase |
            (.spec.nodeName) as $node |
            (.status.startTime) as $startTime |
            # Calculate age in days
            (now - (($startTime | fromdateiso8601) // now)) as $age_seconds |
            ($age_seconds / 86400 | floor | tostring + " days") as $age |
            {
                "service": $service,
                "namespace": $namespace,
                "workload": $workload,
                "worktype": $worktype,
                "node": $node,
                "pod": $name,
                "status": $phase,
                "age": $age
            }
        ' | jq -s 'if length == 0 then [] else . end' >> "$data_file"
    done < "$service_info_file"
    
    # Merge all JSON files
    jq -s 'add' "$data_file" > "${TEMP_DIR}/workloads_data_merged.json"
    
    # Create table layout JSON
    local layout=$(cat <<EOF
{
  "theme": "Blue",
  "columns": [
    {
      "header": "SERVICE",
      "key": "service",
      "datatype": "text",
      "justification": "left",
      "string_limit": 15
    },
    {
      "header": "NAMESPACE",
      "key": "namespace",
      "datatype": "text",
      "justification": "left",
      "string_limit": 14
    },
    {
      "header": "WORKLOAD",
      "key": "workload",
      "datatype": "text",
      "justification": "left",
      "string_limit": 8
    },
    {
      "header": "WORKTYPE",
      "key": "worktype",
      "datatype": "text",
      "justification": "left",
      "string_limit": 8
    },
    {
      "header": "NODE",
      "key": "node",
      "datatype": "text",
      "justification": "left",
      "string_limit": 20
    },
    {
      "header": "POD",
      "key": "pod",
      "datatype": "text",
      "justification": "left",
      "string_limit": 36
    },
    {
      "header": "STATUS",
      "key": "status",
      "datatype": "text",
      "justification": "left",
      "string_limit": 7
    },
    {
      "header": "AGE",
      "key": "age",
      "datatype": "text",
      "justification": "left",
      "string_limit": 7
    }
  ]
}
EOF
)
    
    # Create layout file
    local layout_file=$(create_table_layout "workloads" "$layout")
    
    # Render the table
    render_table "Application Workloads" "$layout_file" "${TEMP_DIR}/workloads_data_merged.json"
    
    return 0
}

# Function to get certificate manager status
get_cert_manager_status() {
    echo "=== Certificate Manager Status ==="
    
    # Create temporary files
    local cert_temp="${TEMP_DIR}/cert_temp.json"
    local display_temp="${TEMP_DIR}/cert_display.json"
    
    debug "Cert temp file: $cert_temp"
    debug "Display temp file: $display_temp"
    
    # Get certificates
    kubectl get certificates -A -o json > "$cert_temp"
    
    # Create a simple JSON array for certificates
    echo "[]" > "$display_temp"

    # Process certificates
    kubectl get certificates -A -o json | jq -r '.items[] | 
        .metadata.namespace as $namespace | 
        .metadata.name as $name | 
        (.spec.dnsNames // [])[] as $domain | 
        $domain + "\t" + $namespace + "\t" + $name
    ' 2>/dev/null | while read -r line; do
        if [ -n "$line" ]; then
            IFS=$'\t' read -r domain namespace cert_name <<< "$line"
            # Get cert status if possible
            status=$(kubectl get certificate -n "$namespace" "$cert_name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
            renewal=$(kubectl get certificate -n "$namespace" "$cert_name" -o jsonpath='{.status.notAfter}' 2>/dev/null || echo "Unknown")
            
            # Calculate days left
            days_left="0"
            if [ "$renewal" != "Unknown" ]; then
                renewal_sec=$(date -d "$renewal" +%s 2>/dev/null || echo "0")
                now_sec=$(date +%s)
                days_left=$(( (renewal_sec - now_sec) / 86400 ))
            fi
            
            # Add to our display array
            jq -n --arg domain "$domain" \
                --arg namespace "$namespace" \
                --arg cert "$cert_name" \
                --arg status "$status" \
                --arg renewal "$renewal" \
                --arg days "$days_left" \
                '{
                    "domain": $domain,
                    "namespace": $namespace,
                    "workload": "Missing",
                    "worktype": "Missing",
                    "certificate": $cert,
                    "status": $status,
                    "renewal": $renewal,
                    "days_left": $days
                }' | jq -s '. + input' "$display_temp" > "${display_temp}.new"
            
            mv "${display_temp}.new" "$display_temp"
        fi
    done

    # If no certificates were found, add a default entry
    if [ ! -s "$display_temp" ] || [ "$(jq '. | length' "$display_temp")" = "0" ]; then
        echo '[{"domain":"No Certificates","namespace":"N/A","workload":"Missing","worktype":"Missing","certificate":"N/A","status":"Unknown","renewal":"N/A","days_left":"0"}]' > "$display_temp"
    fi
    
    # Create table layout JSON
    local layout=$(cat <<EOF
{
  "theme": "Blue",
  "columns": [
    {
      "header": "DOMAIN",
      "key": "domain",
      "datatype": "text",
      "justification": "left",
      "string_limit": 25
    },
    {
      "header": "NAMESPACE",
      "key": "namespace",
      "datatype": "text",
      "justification": "left",
      "string_limit": 14
    },
    {
      "header": "WORKLOAD",
      "key": "workload",
      "datatype": "text",
      "justification": "left",
      "string_limit": 8
    },
    {
      "header": "WORKTYPE",
      "key": "worktype",
      "datatype": "text",
      "justification": "left",
      "string_limit": 8
    },
    {
      "header": "CERTIFICATE",
      "key": "certificate",
      "datatype": "text",
      "justification": "left",
      "string_limit": 17
    },
    {
      "header": "STATUS",
      "key": "status_text",
      "datatype": "text",
      "justification": "left",
      "string_limit": 6
    },
    {
      "header": "RENEWAL",
      "key": "renewal",
      "datatype": "text",
      "justification": "left",
      "string_limit": 20
    },
    {
      "header": "DAYS LEFT",
      "key": "days_left",
      "datatype": "text",
      "justification": "left",
      "string_limit": 9
    }
  ]
}
EOF
)
    
    # Create data file with status text conversion
    jq -r '[.[] | 
        # Convert status from True/False to Active/Inactive
        (.status | if . == "True" then "Active" elif . == "False" then "Inactive" else . end) as $status_text |
        . + {"status_text": $status_text}
    ]' "$display_temp" > "${TEMP_DIR}/cert_display_final.json"
    
    # Create layout file
    local layout_file=$(create_table_layout "certificates" "$layout")
    
    # Render the table
    render_table "Certificate Manager Status" "$layout_file" "${TEMP_DIR}/cert_display_final.json"
    
    # Save certificate domains for mismatch check
    jq -r '.domain' "$display_temp" | sort -u > "${TEMP_DIR}/cert_domains.txt"
    
    return 0
}

# Function to find domains in ingress but not in cert-manager and vice versa
find_domain_mismatches() {
    echo "=== Domain Mismatches ==="
    
    # Check if domain files exist
    if [ ! -f "${TEMP_DIR}/ingress_domains.txt" ] || [ ! -f "${TEMP_DIR}/cert_domains.txt" ]; then
        echo "Domain files not found. Run get_ingress_domains and get_cert_manager_status first."
        return 1
    fi
    
    # Find domains in ingress but not in cert-manager
    local missing_certs=$(comm -23 <(sort "${TEMP_DIR}/ingress_domains.txt") <(sort "${TEMP_DIR}/cert_domains.txt"))
    
    # Find domains in cert-manager but not in ingress
    local unused_certs=$(comm -13 <(sort "${TEMP_DIR}/ingress_domains.txt") <(sort "${TEMP_DIR}/cert_domains.txt"))
    
    # Create data JSON
    local display_temp="${TEMP_DIR}/mismatches_data.json"
    
    if [ -z "$missing_certs" ] && [ -z "$unused_certs" ]; then
        echo '[{ "domain": "No Issues", "status": "OK", "description": "All domains properly configured" }]' > "$display_temp"
    else
        echo "[]" > "$display_temp"
        if [ -n "$missing_certs" ]; then
            echo "$missing_certs" | while read -r domain; do
                if [ -n "$domain" ]; then
                    jq -n --arg domain "$domain" \
                        '{
                            "domain": $domain,
                            "status": "Missing Cert",
                            "description": "Domain has no TLS certificate"
                        }' | jq -s '. + input' "$display_temp" > "${display_temp}.new"
                    
                    mv "${display_temp}.new" "$display_temp"
                fi
            done
        fi
        
        if [ -n "$unused_certs" ]; then
            echo "$unused_certs" | while read -r domain; do
                if [ -n "$domain" ]; then
                    jq -n --arg domain "$domain" \
                        '{
                            "domain": $domain,
                            "status": "Unused Cert",
                            "description": "Certificate not used by any ingress"
                        }' | jq -s '. + input' "$display_temp" > "${display_temp}.new"
                    
                    mv "${display_temp}.new" "$display_temp"
                fi
            done
        fi
    fi
    
    # Create table layout JSON
    local layout=$(cat <<EOF
{
  "theme": "Blue",
  "columns": [
    {
      "header": "DOMAIN",
      "key": "domain",
      "datatype": "text",
      "justification": "left",
      "string_limit": 9
    },
    {
      "header": "STATUS",
      "key": "status",
      "datatype": "text",
      "justification": "left",
      "string_limit": 6
    },
    {
      "header": "DESCRIPTION",
      "key": "description",
      "datatype": "text",
      "justification": "left",
      "string_limit": 25
    }
  ]
}
EOF
)
    
    # Create layout file
    local layout_file=$(create_table_layout "mismatches" "$layout")
    
    # Render the table
    render_table "Domain Mismatches" "$layout_file" "$display_temp"
    
    return 0
}

# Function to check cert-manager and ingress controller health
check_system_health() {
    echo "=== System Health Check ==="
    
    # Create temporary files
    local display_temp="${TEMP_DIR}/health_data.json"
    
    # Start with empty array
    echo "[]" > "$display_temp"
    
    # Add cert-manager pods
    kubectl get pods -n "$CERT_MANAGER_NAMESPACE" -o wide | grep -v NAME | while read -r name ready status restarts age ip node nominated_node readiness_gates; do
        if [ -n "$name" ]; then
            jq -n --arg namespace "$CERT_MANAGER_NAMESPACE" \
                --arg pod "$name" \
                --arg status "$status" \
                --arg node "$node" \
                --arg age "$age" \
                '{
                    "namespace": $namespace,
                    "workload": "Missing",
                    "worktype": "Missing",
                    "node": $node,
                    "pod": $pod,
                    "status": $status,
                    "age": $age
                }' | jq -s '. + input' "$display_temp" > "${display_temp}.new"
            
            mv "${display_temp}.new" "$display_temp"
        fi
    done
    
    # Add ingress-nginx pods
    kubectl get pods -n "$INGRESS_NAMESPACE" -o wide | grep -v NAME | while read -r name ready status restarts age ip node nominated_node readiness_gates; do
        if [ -n "$name" ]; then
            jq -n --arg namespace "$INGRESS_NAMESPACE" \
                --arg pod "$name" \
                --arg status "$status" \
                --arg node "$node" \
                --arg age "$age" \
                '{
                    "namespace": $namespace,
                    "workload": "Missing",
                    "worktype": "Missing",
                    "node": $node,
                    "pod": $pod,
                    "status": $status,
                    "age": $age
                }' | jq -s '. + input' "$display_temp" > "${display_temp}.new"
            
            mv "${display_temp}.new" "$display_temp"
        fi
    done
    
    # If no pods were found, add a default entry
    if [ ! -s "$display_temp" ] || [ "$(jq '. | length' "$display_temp")" = "0" ]; then
        echo '[{"namespace":"No Pods Found","workload":"Missing","worktype":"Missing","node":"N/A","pod":"N/A","status":"Unknown","age":"N/A"}]' > "$display_temp"
    fi
    
    # Create table layout JSON
    local layout=$(cat <<EOF
{
  "theme": "Blue",
  "columns": [
    {
      "header": "NAMESPACE",
      "key": "namespace",
      "datatype": "text",
      "justification": "left",
      "string_limit": 13
    },
    {
      "header": "WORKLOAD",
      "key": "workload",
      "datatype": "text",
      "justification": "left",
      "string_limit": 8
    },
    {
      "header": "WORKTYPE",
      "key": "worktype",
      "datatype": "text",
      "justification": "left",
      "string_limit": 8
    },
    {
      "header": "NODE",
      "key": "node",
      "datatype": "text",
      "justification": "left",
      "string_limit": 20
    },
    {
      "header": "POD",
      "key": "pod",
      "datatype": "text",
      "justification": "left",
      "string_limit": 43
    },
    {
      "header": "STATUS",
      "key": "status",
      "datatype": "text",
      "justification": "left",
      "string_limit": 7
    },
    {
      "header": "AGE",
      "key": "age",
      "datatype": "text",
      "justification": "left",
      "string_limit": 7
    }
  ]
}
EOF
)
    
    # Create layout file
    local layout_file=$(create_table_layout "health" "$layout")
    
    # Render the table
    render_table "System Health Check" "$layout_file" "$display_temp"
    
    return 0
}

# Main function
main() {
    # Run the individual checks
    get_ingress_domains
    get_application_workloads
    get_cert_manager_status
    find_domain_mismatches
    check_system_health
    
    echo "=== Audit Complete (v$VERSION) ==="
}

# Run the main function
main