#!/bin/bash

# DOKS Ingress and Cert-Manager Domain Audit Script
# Requires: kubectl, doctl, jq
# Version: 1.0.19

# Usage: ./dommgmt.sh [--debug]

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Box-drawing characters for tables
TL_CORNER='┌'
TR_CORNER='┐'
BL_CORNER='└'
BR_CORNER='┘'
H_LINE='─'
V_LINE='│'
T_JUNCT='┬'
B_JUNCT='┴'
L_JUNCT='├'
R_JUNCT='┤'
CROSS='┼'

# Configuration
VERSION="1.0.19"
INGRESS_CLASS=${INGRESS_CLASS:-"nginx"}
CERT_MANAGER_NAMESPACE=${CERT_MANAGER_NAMESPACE:-"cert-manager"}
INGRESS_NAMESPACE=${INGRESS_NAMESPACE:-"ingress-nginx"}
DEBUG="false"

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --debug) DEBUG="true"; shift ;;
        *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
    esac
done

echo -e "${BLUE}=== DOKS Ingress and Certificate Manager Audit (v$VERSION) ===${NC}"
echo "Ingress Class: $INGRESS_CLASS"
echo "Cert-Manager Namespace: $CERT_MANAGER_NAMESPACE"
echo "Ingress Namespace: $INGRESS_NAMESPACE"
echo ""

# Function to print debug messages if DEBUG is true
debug() {
    if [ "$DEBUG" = "true" ]; then
        echo -e "${YELLOW}Debug: $@${NC}"
    fi
}

# Function to check if required tools are available
check_dependencies() {
    local missing_deps=()
    
    if ! command -v kubectl &> /dev/null; then
        missing_deps+=("kubectl")
    fi
    
    if ! command -v doctl &> /dev/null; then
        missing_deps+=("doctl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}Missing dependencies: ${missing_deps[*]}${NC}"
        echo "Please install the missing tools and try again."
        exit 1
    fi
    debug "JQ version: $(jq --version)"
}

# Function to calculate max width for each column
calculate_widths() {
    local data_file="$1"
    local -n widths_ref=$2
    local -a headers=("${@:3}")
    
    # Initialize widths with header lengths
    for i in "${!headers[@]}"; do
        widths_ref["${headers[i]}"]=${#headers[i]}
    done
    
    # Scan data for max widths
    while IFS=$'\t' read -r line; do
        IFS=$'\t' read -ra values <<< "$line"
        for i in "${!headers[@]}"; do
            # Strip ANSI codes for length calculation
            local clean_value=$(echo "${values[i]}" | sed -r 's/\x1B\[[0-9;]*m//g')
            if [ ${#clean_value} -gt ${widths_ref[${headers[i]}]} ]; then
                widths_ref["${headers[i]}"]=${#clean_value}
            fi
        done
    done < "$data_file"
}

# Function to render a table
render_table() {
    local data_file="$1"
    local -n widths_ref=$2
    local -a headers=("${@:3}")
    
    # Top border
    printf "$TL_CORNER"
    for header in "${headers[@]}"; do
        printf "$H_LINE%.0s" $(seq 1 $((widths_ref[$header] + 2)))
        printf "$T_JUNCT"
    done
    printf "\b$TR_CORNER\n"
    
    # Header row
    printf "$V_LINE"
    for header in "${headers[@]}"; do
        printf " %-${widths_ref[$header]}s $V_LINE" "$header"
    done
    printf "\n"
    
    # Separator
    printf "$L_JUNCT"
    for header in "${headers[@]}"; do
        printf "$H_LINE%.0s" $(seq 1 $((widths_ref[$header] + 2)))
        printf "$CROSS"
    done
    printf "\b$R_JUNCT\n"
    
    # Data rows
    while IFS=$'\t' read -r line; do
        IFS=$'\t' read -ra values <<< "$line"
        printf "$V_LINE"
        for i in "${!headers[@]}"; do
            printf " %-${widths_ref[${headers[i]}]}s $V_LINE" "${values[i]}"
        done
        printf "\n"
    done < "$data_file"
    
    # Bottom border
    printf "$BL_CORNER"
    for header in "${headers[@]}"; do
        printf "$H_LINE%.0s" $(seq 1 $((widths_ref[$header] + 2)))
        printf "$B_JUNCT"
    done
    printf "\b$BR_CORNER\n"
}

# Function to get ingress domains and their backends
get_ingress_domains() {
    echo -e "${BLUE}=== Ingress Controller Domains ===${NC}"
    
    # Create temporary files
    local ingress_temp
    ingress_temp=$(mktemp) || {
        echo -e "${RED}Failed to create temp file with mktemp${NC}"
        exit 1
    }
    local domains_temp
    domains_temp=$(mktemp) || {
        echo -e "${RED}Failed to create temp file with mktemp${NC}"
        exit 1
    }
    local display_temp
    display_temp=$(mktemp) || {
        echo -e "${RED}Failed to create temp file with mktemp${NC}"
        exit 1
    }
    debug "Ingress temp file: $ingress_temp"
    debug "Domains temp file: $domains_temp"
    debug "Display temp file: $display_temp"
    
    # Get ingress resources
    if ! kubectl get ingress -A -o json > "$ingress_temp" 2>/tmp/ingress_kubectl_error.log; then
        echo -e "${RED}Failed to fetch Ingress resources. Check kubectl access or cluster status.${NC}"
        echo -e "${YELLOW}Kubectl errors saved to /tmp/ingress_kubectl_error.log${NC}"
        cat /tmp/ingress_kubectl_error.log
        rm -f "$ingress_temp" "$domains_temp" "$display_temp"
        exit 1
    fi
    
    # Check if output is empty or malformed
    if [ ! -s "$ingress_temp" ]; then
        echo -e "${YELLOW}No Ingress resources found. Check your cluster or INGRESS_CLASS ($INGRESS_CLASS).${NC}"
        echo -e "${YELLOW}Raw output saved to /tmp/ingress_debug.json for inspection.${NC}"
        cp "$ingress_temp" /tmp/ingress_debug.json
        rm -f "$ingress_temp" "$domains_temp" "$display_temp"
        echo ""
        return 1
    fi
    debug "Ingress JSON written to $ingress_temp, size: $(wc -c < "$ingress_temp") bytes"
    if ! jq -e . "$ingress_temp" >/dev/null 2>/tmp/ingress_json_check.log; then
        echo -e "${RED}Ingress JSON is malformed.${NC}"
        echo -e "${YELLOW}Raw output saved to /tmp/ingress_debug.json${NC}"
        echo -e "${YELLOW}JSON check errors saved to /tmp/ingress_json_check.log${NC}"
        cp "$ingress_temp" /tmp/ingress_debug.json
        cat /tmp/ingress_json_check.log
        rm -f "$ingress_temp" "$domains_temp" "$display_temp"
        echo ""
        return 1
    fi
    debug "Ingress JSON is valid"
    
    # Extract ingress data
    local jq_filter='.items[]? | 
        select((.spec.ingressClassName // "") == "'$INGRESS_CLASS'" or 
               (.metadata.annotations["kubernetes.io/ingress.class"] // "") == "'$INGRESS_CLASS'") |
        .metadata.namespace as $ns |
        .metadata.name as $name |
        .metadata.labels["workload"]? as $workload |
        .metadata.labels["worktype"]? as $worktype |
        (.spec.tls // []) as $tls_hosts |
        (.spec.rules // [])[]? | 
        .host as $host |
        (.http.paths // [])[]? | 
        {
            namespace: $ns,
            ingress: $name,
            host: ($host // "(default)"),
            path: (.path // "/"),
            service: (.backend.service.name // "N/A"),
            port: (.backend.service.port.number // "N/A"),
            has_tls: ([$tls_hosts[]?.hosts[]? | select(. == ($host // ""))] | length > 0),
            workload: ($workload // "Missing"),
            worktype: ($worktype // "Missing")
        }'
    if ! jq -r "$jq_filter" "$ingress_temp" > "$domains_temp" 2>/tmp/ingress_jq_error.log; then
        echo -e "${RED}JQ parsing failed for Ingress resources.${NC}"
        echo -e "${YELLOW}Raw JSON saved to /tmp/ingress_debug.json${NC}"
        echo -e "${YELLOW}JQ error details saved to /tmp/ingress_jq_error.log${NC}"
        debug "Ingress JSON content:"
        cat "$ingress_temp"
        cp "$ingress_temp" /tmp/ingress_debug.json
        cat /tmp/ingress_jq_error.log
        rm -f "$ingress_temp" "$domains_temp" "$display_temp"
        echo ""
        return 1
    fi
    debug "JQ output written to $domains_temp, size: $(wc -c < "$domains_temp") bytes"
    debug "Domains temp content:"
    if [ "$DEBUG" = "true" ]; then
        cat "$domains_temp"
    fi
    
    # Prepare display data
    if ! jq -s -r '.[] | 
        [
            .host // "N/A",
            .namespace // "N/A",
            .workload // "Missing",
            .worktype // "Missing",
            .ingress // "N/A",
            (.service // "N/A") + ":" + (.port // "N/A" | tostring),
            .path // "/",
            (if .has_tls then "YES" else "NO" end)
        ] | @tsv' "$domains_temp" > "$display_temp" 2>/tmp/ingress_display_error.log; then
        echo -e "${RED}JQ display parsing failed.${NC}"
        echo -e "${YELLOW}JQ error details saved to /tmp/ingress_display_error.log${NC}"
        cat /tmp/ingress_display_error.log
        debug "Domains temp content for inspection:"
        cat "$domains_temp"
        rm -f "$ingress_temp" "$domains_temp" "$display_temp"
        echo ""
        return 1
    fi
    debug "Display temp content:"
    if [ "$DEBUG" = "true" ]; then
        cat "$display_temp"
    fi
    
    # Render table
    if [ ! -s "$display_temp" ]; then
        echo -e "${YELLOW}No Ingress rules found for class $INGRESS_CLASS${NC}"
        rm -f "$ingress_temp" "$domains_temp" "$display_temp"
        echo ""
        return 0
    fi
    
    local -A widths
    local headers=("DOMAIN" "NAMESPACE" "WORKLOAD" "WORKTYPE" "INGRESS" "SERVICE:PORT" "PATH" "TLS")
    calculate_widths "$display_temp" widths "${headers[@]}"
    render_table "$display_temp" widths "${headers[@]}"
    
    # Store domains for mismatch check
    jq -r 'select(.host != "(default)") | .host // empty' "$domains_temp" | sort -u | tr '[:upper:]' '[:lower:]' > "$ingress_domains_temp"
    mv "$ingress_domains_temp" /tmp/ingress_domains.txt
    debug "Ingress domains for mismatch check:"
    if [ "$DEBUG" = "true" ]; then
        cat /tmp/ingress_domains.txt
    fi
    
    rm -f "$ingress_temp" "$domains_temp" "$display_temp"
    echo ""
}

# Function to get certificate manager status
get_cert_manager_status() {
    echo -e "${BLUE}=== Certificate Manager Status ===${NC}"
    
    # Check if cert-manager is installed
    if ! kubectl get crd certificates.cert-manager.io &>/dev/null; then
        echo -e "${YELLOW}cert-manager CRDs not found. Skipping certificate status check.${NC}"
        echo "" > /tmp/cert_domains.txt
        echo ""
        return
    fi
    
    # Get certificates
    local cert_temp
    cert_temp=$(mktemp) || {
        echo -e "${RED}Failed to create temp file with mktemp${NC}"
        exit 1
    }
    local display_temp
    display_temp=$(mktemp) || {
        echo -e "${RED}Failed to create temp file with mktemp${NC}"
        exit 1
    }
    debug "Cert temp file: $cert_temp"
    debug "Display temp file: $display_temp"
    
    if ! kubectl get certificates -A -o json > "$cert_temp" 2>/tmp/cert_kubectl_error.log; then
        echo -e "${YELLOW}No certificates found or unable to access certificates.${NC}"
        echo -e "${YELLOW}Kubectl errors saved to /tmp/cert_kubectl_error.log${NC}"
        cat /tmp/cert_kubectl_error.log
        echo "" > /tmp/cert_domains.txt
        rm -f "$cert_temp" "$display_temp"
        echo ""
        return
    fi
    
    # Prepare display data
    if ! jq -r '.items[]? |
        .metadata.namespace as $ns |
        .metadata.name as $name |
        .metadata.labels["workload"]? as $workload |
        .metadata.labels["worktype"]? as $worktype |
        (.spec.dnsNames // [])[]? as $domain |
        .status as $status |
        [
            $domain // "N/A",
            $ns // "N/A",
            ($workload // "Missing"),
            ($worktype // "Missing"),
            $name // "N/A",
            ($status.conditions[]? | select(.type == "Ready") | .status // "Unknown"),
            ($status.notAfter // "N/A")
        ] | @tsv' "$cert_temp" > "$display_temp" 2>/tmp/cert_display_error.log; then
        echo -e "${RED}JQ display parsing failed for certificates.${NC}"
        echo -e "${YELLOW}JQ error details saved to /tmp/cert_display_error.log${NC}"
        cat /tmp/cert_display_error.log
        rm -f "$cert_temp" "$display_temp"
        echo ""
        return 1
    fi
    debug "Display temp content:"
    if [ "$DEBUG" = "true" ]; then
        cat "$display_temp"
    fi
    
    # Render table
    if [ ! -s "$display_temp" ]; then
        echo -e "${YELLOW}No certificates found.${NC}"
        echo "" > /tmp/cert_domains.txt
        rm -f "$cert_temp" "$display_temp"
        echo ""
        return 0
    fi
    
    local -A widths
    local headers=("DOMAIN" "NAMESPACE" "WORKLOAD" "WORKTYPE" "CERTIFICATE" "STATUS" "RENEWAL")
    calculate_widths "$display_temp" widths "${headers[@]}"
    render_table "$display_temp" widths "${headers[@]}"
    
    # Store certificate domains
    if ! jq -r '.items[]? | .spec.dnsNames[]? // empty' "$cert_temp" | sort -u | tr '[:upper:]' '[:lower:]' > "$cert_domains_temp" 2>/tmp/cert_domains_error.log; then
        echo -e "${RED}Failed to extract certificate domains.${NC}"
        echo -e "${YELLOW}Error details saved to /tmp/cert_domains_error.log${NC}"
        cat /tmp/cert_domains_error.log
        rm -f "$cert_temp" "$display_temp" "$cert_domains_temp"
        echo ""
        return 1
    fi
    mv "$cert_domains_temp" /tmp/cert_domains.txt
    debug "Certificate domains for mismatch check:"
    if [ "$DEBUG" = "true" ]; then
        cat /tmp/cert_domains.txt
    fi
    
    rm -f "$cert_temp" "$display_temp"
    echo ""
}

# Function to find domains in ingress but not in cert-manager and vice versa
find_domain_mismatches() {
    echo -e "${BLUE}=== Domain Mismatches ===${NC}"
    
    if [ ! -f /tmp/ingress_domains.txt ] || [ ! -f /tmp/cert_domains.txt ]; then
        echo -e "${RED}Error: Domain lists not found. Run the full audit first.${NC}"
        return 1
    fi
    
    # Domains in ingress but not in cert-manager
    local missing_certs=$(comm -23 /tmp/ingress_domains.txt /tmp/cert_domains.txt)
    if [ -z "$missing_certs" ]; then
        echo -e "${GREEN}✓ All ingress domains have corresponding certificates!${NC}"
    else
        echo -e "${RED}✗ Domains in ingress missing certificates:${NC}"
        echo "$missing_certs" | while read -r domain; do
            if [ -n "$domain" ]; then
                echo -e "  ${RED}• $domain${NC}"
            fi
        done
    fi
    echo ""
    
    # Domains in cert-manager but not in ingress
    local unused_certs=$(comm -13 /tmp/ingress_domains.txt /tmp/cert_domains.txt)
    if [ -z "$unused_certs" ]; then
        echo -e "${GREEN}✓ All certificate domains are used by ingress!${NC}"
    else
        echo -e "${YELLOW}⚠ Certificates not used by ingress (review if unneeded):${NC}"
        echo "$unused_certs" | while read -r domain; do
            if [ -n "$domain" ]; then
                echo -e "  ${YELLOW}• $domain${NC}"
            fi
        done
    fi
    echo ""
}

# Function to check cert-manager and ingress controller health
check_system_health() {
    echo -e "${BLUE}=== System Health Check ===${NC}"
    
    # Check cert-manager pods
    echo "Cert-Manager Pods:"
    local cert_pods
    cert_pods=$(kubectl get pods -n "$CERT_MANAGER_NAMESPACE" -l app.kubernetes.io/instance=cert-manager -o wide 2>/dev/null || echo "ERROR")
    if [ "$cert_pods" = "ERROR" ] || [ -z "$cert_pods" ]; then
        echo -e "${RED}✗ No cert-manager pods found in namespace $CERT_MANAGER_NAMESPACE${NC}"
    else
        echo -e "$cert_pods" | while IFS= read -r line; do
            if echo "$line" | grep -q "Running"; then
                echo -e "${GREEN}$line${NC}"
            else
                echo -e "${RED}$line${NC}"
            fi
        done
    fi
    echo ""
    
    # Check ingress controller pods
    echo "Ingress Controller Pods:"
    local ingress_pods
    ingress_pods=$(kubectl get pods -n "$INGRESS_NAMESPACE" -l app.kubernetes.io/name=ingress-nginx -o wide 2>/dev/null || echo "ERROR")
    if [ "$ingress_pods" = "ERROR" ] || [ -z "$ingress_pods" ]; then
        echo -e "${RED}✗ No ingress-nginx pods found in namespace $INGRESS_NAMESPACE${NC}"
    else
        echo -e "$ingress_pods" | while IFS= read -r line; do
            if echo "$line" | grep -q "Running"; then
                echo -e "${GREEN}$line${NC}"
            else
                echo -e "${RED}$line${NC}"
            fi
        done
    fi
    echo ""
}

# Main execution
main() {
    check_dependencies
    
    echo "Checking cluster connectivity..."
    kubectl cluster-info >/dev/null 2>&1 || {
        echo -e "${RED}Cannot connect to Kubernetes cluster. Check your kubectl configuration.${NC}"
        exit 1
    }
    
    local cert_domains_temp
    cert_domains_temp=$(mktemp) || {
        echo -e "${RED}Failed to create temp file with mktemp${NC}"
        exit 1
    }
    local ingress_domains_temp
    ingress_domains_temp=$(mktemp) || {
        echo -e "${RED}Failed to create temp file with mktemp${NC}"
        exit 1
    }
    get_ingress_domains
    get_cert_manager_status
    find_domain_mismatches
    check_system_health
    
    # Cleanup
    rm -f /tmp/ingress_domains.txt /tmp/cert_domains.txt /tmp/ingress_kubectl_error.log /tmp/ingress_debug.json /tmp/ingress_json_check.log /tmp/ingress_jq_error.log /tmp/ingress_display_error.log /tmp/cert_kubectl_error.log /tmp/cert_display_error.log /tmp/cert_domains_error.log "$ingress_domains_temp" "$cert_domains_temp"
    
    echo -e "${GREEN}=== Audit Complete (v$VERSION) ===${NC}"
}

# Run the script
main "$@"
