#!/bin/bash

# Version: 1.0.20

# Usage: ./dommgmt.sh [--debug]

# Configuration
VERSION="1.0.20"
INGRESS_CLASS=${INGRESS_CLASS:-"nginx"}
CERT_MANAGER_NAMESPACE=${CERT_MANAGER_NAMESPACE:-"cert-manager"}
INGRESS_NAMESPACE=${INGRESS_NAMESPACE:-"ingress-nginx"}
DEBUG="false"

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --debug) DEBUG="true"; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "DOKS Ingress and Certificate Manager Audit (v$VERSION) ==="
echo "Ingress Class: $INGRESS_CLASS"
echo "Cert-Manager Namespace: $CERT_MANAGER_NAMESPACE"
echo "Ingress Namespace: $INGRESS_NAMESPACE"

# Function to print debug messages if DEBUG is true
debug() {
    if [ "$DEBUG" = "true" ]; then
        echo "Debug: $@"
    fi
}

# Function to get ingress domains and their backends
get_ingress_domains() {
    echo "=== Starting Ingress and Service Discovery ==="
    
    # Create temporary files
    local ingress_temp=$(mktemp)
    local domains_temp=$(mktemp)
    local display_temp=$(mktemp)
    local service_info_file=$(mktemp)
    
    # Store service_info_path for later use in main
    echo "$service_info_file" > /tmp/service_info_path.txt
    
    debug "Service info path: $service_info_file"
    
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
    
    debug "Ingress temp file: $ingress_temp"
    debug "Domains temp file: $domains_temp"
    debug "Display temp file: $display_temp"
    
    # Store domains for mismatches check
    grep -v "(default)" "$domains_temp" | jq -r '.host' | sort -u > /tmp/domains.txt
    
    # Store service info for workloads section
    jq -r '"\(.namespace)\t\(.service)"' "$domains_temp" | sort -u > "$service_info_file"
    
    # Print domains table
    echo "=== Ingress Controller Domains ==="
    
    # Prepare data for table display
    jq -s '[.[] | {
        domain: .host,
        namespace: .namespace,
        workload: .workload,
        worktype: .worktype,
        ingress: .ingress,
        service_port: (.service + ":" + (.port | tostring)),
        path: .path,
        tls: (if .has_tls then "YES" else "NO" end)
    }]' "$domains_temp" > "$display_temp"
    
    debug "Domains temp content:"
    if [ "$DEBUG" = "true" ]; then
        cat "$domains_temp"
    fi
    
    debug "Display temp content:"
    if [ "$DEBUG" = "true" ]; then
        cat "$display_temp"
    fi
    
    # Print table header
    echo "╭───────────────────────┬────────────────┬──────────┬──────────┬─────────────────┬────────────────────┬──────┬─────┬╮"
    echo "│ DOMAIN                │ NAMESPACE      │ WORKLOAD │ WORKTYPE │ INGRESS         │ SERVICE:PORT       │ PATH │ TLS │"
    echo "├───────────────────────┼────────────────┼──────────┼──────────┼─────────────────┼────────────────────┼──────┼─────┼┤"
    
    # Print table rows
    jq -r '.[] | "│ \(.domain | tostring | .[0:25] + (if 25 - length > 0 then " " * (25 - length) else "" end)) │ \(.namespace | tostring | .[0:14] + (if 14 - length > 0 then " " * (14 - length) else "" end)) │ \(.workload | tostring | .[0:8] + (if 8 - length > 0 then " " * (8 - length) else "" end)) │ \(.worktype | tostring | .[0:8] + (if 8 - length > 0 then " " * (8 - length) else "" end)) │ \(.ingress | tostring | .[0:15] + (if 15 - length > 0 then " " * (15 - length) else "" end)) │ \(.service_port | tostring | .[0:18] + (if 18 - length > 0 then " " * (18 - length) else "" end)) │ \(.path | tostring | .[0:4] + (if 4 - length > 0 then " " * (4 - length) else "" end)) │ \(.tls | tostring | .[0:3] + (if 3 - length > 0 then " " * (3 - length) else "" end)) │"' "$display_temp"
    
    # Print table footer
    echo "╰───────────────────────┴────────────────┴──────────┴──────────┴─────────────────┴────────────────────┴──────┴─────┴╯"
    
    # Save domains for mismatch check
    jq -r 'select(.host != "(default)") | .host' "$domains_temp" | sort -u > /tmp/ingress_domains.txt
    debug "Ingress domains for mismatch check:"
    if [ "$DEBUG" = "true" ]; then
        cat /tmp/ingress_domains.txt
    fi
    
    # Cleanup
    rm -f "$ingress_temp" "$domains_temp" "$display_temp"
    
    # Return service info file path
    return 0
}

# Function to get application workloads
get_application_workloads() {
    local service_info_file="$1"
    
    if [ ! -f "$service_info_file" ]; then
        debug "No service info file found or empty result from get_ingress_domains"
        echo "No ingress resources found to process workloads"
        return 1
    fi
    
    debug "Found service info file, processing workloads"
    echo "=== Application Workloads ==="
    
    # Prepare data for table display
    local display_temp=$(mktemp)
    
    # Print table header
    echo "╭─────────────────┬────────────────┬──────────┬──────────┬──────────────────────┬────────────────────────────────┬─────────┬─────────┬╮"
    echo "│ SERVICE         │ NAMESPACE      │ WORKLOAD │ WORKTYPE │ NODE                 │ POD                            │ STATUS  │ AGE     │"
    echo "├─────────────────┼────────────────┼──────────┼──────────┼──────────────────────┼────────────────────────────────┼─────────┼─────────┼┤"
    
    # Process each service and namespace
    while IFS=$'\t' read -r namespace service; do
        if [ -z "$namespace" ] || [ -z "$service" ]; then
            continue
        fi
        
        debug "Processing service: $service in namespace: $namespace"
        
        # Get service selector
        local selector=$(kubectl get service "$service" -n "$namespace" -o jsonpath='{.spec.selector}' 2>/dev/null)
        if [ -z "$selector" ]; then
            echo "│ $service | $namespace | Missing | Missing | Service not found or has no selector | N/A | N/A | N/A │"
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
        
        # Get service ports
        local service_ports=$(kubectl get service "$service" -n "$namespace" -o jsonpath='{.spec.ports}' 2>/dev/null)
        local ports_formatted=$(echo "$service_ports" | jq -r 'map("\(.port):\(.targetPort)/\(.protocol)") | join(", ")')
        debug "Service ports: $ports_formatted"
        
        # Get pods matching the selector
        local pod_json=$(kubectl get pods -n "$namespace" -l "$selector_labels" -o json 2>/dev/null)
        debug "Pod JSON for $service:"
        if [ "$DEBUG" = "true" ]; then
            echo "$pod_json" | jq .
        fi
        
        # Process each pod
        # Pass service and namespace as arguments to JQ
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
            "│ " + 
            ($service | tostring | .[0:15] + (if 15 - length > 0 then " " * (15 - length) else "" end)) + " │ " + 
            ($namespace | tostring | .[0:14] + (if 14 - length > 0 then " " * (14 - length) else "" end)) + " │ " + 
            ($workload | tostring | .[0:8] + (if 8 - length > 0 then " " * (8 - length) else "" end)) + " │ " + 
            ($worktype | tostring | .[0:8] + (if 8 - length > 0 then " " * (8 - length) else "" end)) + " │ " + 
            ($node | tostring | .[0:20] + (if 20 - length > 0 then " " * (20 - length) else "" end)) + " │ " + 
            ($name | tostring | .[0:36] + (if 36 - length > 0 then " " * (36 - length) else "" end)) + " │ " + 
            ($phase | tostring | .[0:7] + (if 7 - length > 0 then " " * (7 - length) else "" end)) + " │ " + 
            ($age | tostring | .[0:7] + (if 7 - length > 0 then " " * (7 - length) else "" end)) + " │"
        ' >> "$display_temp"
    done < "$service_info_file"
    
    # Print table content
    cat "$display_temp"
    
    # Print table footer
    echo "╰─────────────────┴────────────────┴──────────┴──────────┴──────────────────────┴────────────────────────────────┴─────────┴─────────┴╯"
    
    # Cleanup
    rm -f "$display_temp"
}

# Function to get certificate manager status
get_cert_manager_status() {
    echo "=== Certificate Manager Status ==="
    
    # Create temporary files
    local cert_temp=$(mktemp)
    local display_temp=$(mktemp)
    
    debug "Cert temp file: $cert_temp"
    debug "Display temp file: $display_temp"
    
    # Get certificates
    kubectl get certificates -A -o json > "$cert_temp"
    
    # Create a very simple JSON array for certificates with minimal assumptions
    echo "[]" > "$display_temp"

    # Use a simpler approach for certificates
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
            
            # Use jq to add to our display array
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

    # Ensure the display_temp has content
    if [ ! -s "$display_temp" ]; then
        echo '[{"domain":"No Certificates","namespace":"N/A","workload":"Missing","worktype":"Missing","certificate":"N/A","status":"Unknown","renewal":"N/A","days_left":"0"}]' > "$display_temp"
    fi
    
    # Print table header
    echo "╭───────────────────────┬────────────────┬──────────┬──────────┬───────────────────┬────────┬──────────────────────┬───────────┬╮"
    echo "│ DOMAIN                │ NAMESPACE      │ WORKLOAD │ WORKTYPE │ CERTIFICATE       │ STATUS │ RENEWAL              │ DAYS LEFT │"
    echo "├───────────────────────┼────────────────┼──────────┼──────────┼───────────────────┼────────┼──────────────────────┼───────────┼┤"
    
    # Print table rows
    jq -r '.[] | 
        # Convert status from True/False to Active/Inactive
        (.status | if . == "True" then "Active" elif . == "False" then "Inactive" else . end) as $status_text |
        "│ " + 
        (.domain | tostring | .[0:25] + (if 25 - length > 0 then " " * (25 - length) else "" end)) + " │ " + 
        (.namespace | tostring | .[0:14] + (if 14 - length > 0 then " " * (14 - length) else "" end)) + " │ " + 
        (.workload | tostring | .[0:8] + (if 8 - length > 0 then " " * (8 - length) else "" end)) + " │ " + 
        (.worktype | tostring | .[0:8] + (if 8 - length > 0 then " " * (8 - length) else "" end)) + " │ " + 
        (.certificate | tostring | .[0:17] + (if 17 - length > 0 then " " * (17 - length) else "" end)) + " │ " + 
        ($status_text | tostring | .[0:6] + (if 6 - length > 0 then " " * (6 - length) else "" end)) + " │ " + 
        (.renewal | tostring | .[0:20] + (if 20 - length > 0 then " " * (20 - length) else "" end)) + " │ " + 
        (.days_left | tostring | .[0:9] + (if 9 - length > 0 then " " * (9 - length) else "" end)) + " │"
    ' "$display_temp"
    
    # Print table footer
    echo "╰───────────────────────┴────────────────┴──────────┴──────────┴───────────────────┴────────┴──────────────────────┴───────────┴╯"
    
    # Save certificate domains for mismatch check
    jq -r '.domain' "$display_temp" | sort -u > /tmp/cert_domains.txt
    debug "Certificate domains for mismatch check:"
    if [ "$DEBUG" = "true" ]; then
        cat /tmp/cert_domains.txt
    fi
    
    # Cleanup
    rm -f "$cert_temp" "$display_temp"
}

# Function to find domains in ingress but not in cert-manager and vice versa
find_domain_mismatches() {
    echo "=== Domain Mismatches ==="
    
    # Check if domain files exist
    if [ ! -f /tmp/ingress_domains.txt ] || [ ! -f /tmp/cert_domains.txt ]; then
        echo "Domain files not found. Run get_ingress_domains and get_cert_manager_status first."
        return 1
    fi
    
    # Find domains in ingress but not in cert-manager
    local missing_certs=$(comm -23 <(sort /tmp/ingress_domains.txt) <(sort /tmp/cert_domains.txt))
    
    # Find domains in cert-manager but not in ingress
    local unused_certs=$(comm -13 <(sort /tmp/ingress_domains.txt) <(sort /tmp/cert_domains.txt))
    
    # Print results
    local display_temp=$(mktemp)
    
    if [ -z "$missing_certs" ] && [ -z "$unused_certs" ]; then
        echo '{ "domain": "No Issues", "status": "OK", "description": "All domains properly configured" }' > "$display_temp"
    else
        if [ -n "$missing_certs" ]; then
            echo "$missing_certs" | while read -r domain; do
                if [ -n "$domain" ]; then
                    echo '{ "domain": "'"$domain"'", "status": "Missing Cert", "description": "Domain has no TLS certificate" }' >> "$display_temp"
                fi
            done
        fi
        
        if [ -n "$unused_certs" ]; then
            echo "$unused_certs" | while read -r domain; do
                if [ -n "$domain" ]; then
                    echo '{ "domain": "'"$domain"'", "status": "Unused Cert", "description": "Certificate not used by any ingress" }' >> "$display_temp"
                fi
            done
        fi
    fi
    
    # Print table header
    echo "╭───────────┬────────┬─────────────────────────────────┬╮"
    echo "│ DOMAIN    │ STATUS │ DESCRIPTION                     │"
    echo "├───────────┼────────┼─────────────────────────────────┼┤"
    
    # Print table rows
    jq -s -r '.[] | 
        "│ " + 
        (.domain | tostring | .[0:9] + (if 9 - length > 0 then " " * (9 - length) else "" end)) + " │ " + 
        (.status | tostring | .[0:6] + (if 6 - length > 0 then " " * (6 - length) else "" end)) + " │ " + 
        (.description | tostring | .[0:25] + (if 25 - length > 0 then " " * (25 - length) else "" end)) + " │"
    ' "$display_temp"
    
    # Print table footer
    echo "╰───────────┴────────┴─────────────────────────────────┴╯"
    
    # Cleanup
    rm -f "$display_temp"
}

# Function to check cert-manager and ingress controller health
check_system_health() {
    echo "=== System Health Check ==="
    
    # Create temporary files
    local display_temp=$(mktemp)
    
    # Get system component data directly
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
    
    # Print table header
    echo "╭───────────────┬──────────┬──────────┬──────────────────────┬───────────────────────────────────────────┬─────────┬─────────┬╮"
    echo "│ NAMESPACE     │ WORKLOAD │ WORKTYPE │ NODE                 │ POD                                       │ STATUS  │ AGE     │"
    echo "├───────────────┼──────────┼──────────┼──────────────────────┼───────────────────────────────────────────┼─────────┼─────────┼┤"
    
    # Print table rows
    jq -r '.[0] + .[1] | .[] | 
        "│ " + 
        (.namespace | tostring | .[0:13] + (if 13 - length > 0 then " " * (13 - length) else "" end)) + " │ " + 
        (.workload | tostring | .[0:8] + (if 8 - length > 0 then " " * (8 - length) else "" end)) + " │ " + 
        (.worktype | tostring | .[0:8] + (if 8 - length > 0 then " " * (8 - length) else "" end)) + " │ " + 
        (.node | tostring | .[0:20] + (if 20 - length > 0 then " " * (20 - length) else "" end)) + " │ " + 
        (.pod | tostring | .[0:43] + (if 43 - length > 0 then " " * (43 - length) else "" end)) + " │ " + 
        (.status | tostring | .[0:7] + (if 7 - length > 0 then " " * (7 - length) else "" end)) + " │ " + 
        (.age | tostring | .[0:7] + (if 7 - length > 0 then " " * (7 - length) else "" end)) + " │"
    ' "$display_temp"
    
    # Print table footer
    echo "╰───────────────┴──────────┴──────────┴──────────────────────┴───────────────────────────────────────────┴─────────┴─────────┴╯"
    
    # Cleanup
    rm -f "$display_temp"
}

# Main function
main() {
    # Run the individual checks
    service_info_path=$(get_ingress_domains)
    
    # Check if service_info_path.txt exists and read from it
    if [ -f /tmp/service_info_path.txt ]; then
        service_info_path=$(cat /tmp/service_info_path.txt)
        debug "Service info path: $service_info_path"
        get_application_workloads "$service_info_path"
    else
        debug "No service info path file found"
    fi
    
    get_cert_manager_status
    find_domain_mismatches
    check_system_health
    
    echo "=== Audit Complete (v$VERSION) ==="
}

# Run the main function
main