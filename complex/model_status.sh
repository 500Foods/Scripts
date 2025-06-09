#!/bin/bash
# 
# model_status.sh - AI Model Health Monitoring Script
# 
# Description: Monitors AI model endpoints, tracks their status, and reports to HomeAssistant
# Author: Your Name
# License: MIT
#
# Version History:
# ================
#
# v0.013 (2025-06-01) - Home Assistant Integration
# v0.012 (2025-05-31) - Implemented database updates for Pinged/Ponged timestamps
# v0.011 (2025-05-31) - Added Ollama support for local model checking
# v0.010 (2025-05-31) - Added Anthropic support and improved success detection
# v0.009 (2025-05-31) - Fixed quote handling by parsing JSON properly at fetch time
# v0.008 (2025-05-31) - Added model checking loop with xAI engine support
# v0.007 (2025-05-30) - Added endpoint validation and response storage for HA
# v0.006 (2025-05-30) - Reorganized main function for better readability
# v0.005 (2025-05-30) - Fixed JSON handling for model query results
# v0.004 (2025-05-30) - Execute model query and parse results
# v0.003 (2025-05-30) - Switched to JSON output from PostgreSQL for reliable parsing
# v0.002 (2025-05-30) - Database connection working, improved code structure
# v0.001 (2025-05-30) - Initial skeleton with database queries
#
# For Developers:
# ===============
# - Main function should be at bottom, orchestrating simple steps
# - Keep functions short and focused on single tasks
# - Use descriptive function names that read like documentation
# - Modular design for easy maintenance and testing
# - Debug output should be comprehensive but not interfere with normal operation
# - All database queries should be parameterized where possible
# - Error messages should be actionable
# - Remember to update version number with each change
#
# Dependencies:
#   - PostgreSQL client (psql) - authentication via ~/.pgpass 
#   - HomeAssistant with API access - authentication via HA_URL and HA_TOKEN
#   - jq for JSON parsing
#   - curl for API calls

# Ensure we're getting env vars like HA_TOKEN and HA_URL
source "$HOME/.bashrc"

# Script version
readonly SCRIPT_NAME="model_status.sh"
readonly SCRIPT_VERSION="0.012"

# Exit on error, undefined variables, pipe failures
set -euo pipefail

# Global flags
DEBUG=0
VERBOSE=0
DRY_RUN=0

# Global variables
QUERY_GET_MODELS=""
QUERY_UPDATE_MODEL=""
declare -A MODELS=()  # Changed to associative array for clean data storage
declare -A MODEL_CHECK_RESULTS=()
DB_HOST=""
DB_PORT=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""

# ANSI color codes for output
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_RESET='\033[0m'

#######################
# Utility Functions
#######################

log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_debug() {
    if [[ $DEBUG -eq 1 ]]; then
        echo -e "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
    fi
}

show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

AI Model Health Monitoring Script - Monitors AI model endpoints and reports status

OPTIONS:
    -h, --help      Show this help message and exit
    -d, --debug     Enable debug mode (verbose output)
    -v, --version   Show version information and exit
    --dry-run       Run without making actual changes

EXAMPLES:
    $SCRIPT_NAME              # Run with default settings
    $SCRIPT_NAME -d           # Run with debug output
    $SCRIPT_NAME --dry-run    # Test without updating database
    $SCRIPT_NAME --help       # Show this help message

CONFIGURATION:
    The script expects a .pgpass file in your home directory with PostgreSQL credentials.
    Format: hostname:port:database:username:password

EOF
}

show_version() {
    echo "$SCRIPT_NAME version $SCRIPT_VERSION"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--debug)
                DEBUG=1
                log_info "Debug mode enabled"
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            --dry-run)
                DRY_RUN=1
                log_info "Dry run mode enabled"
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use $SCRIPT_NAME --help for usage information"
                exit 1
                ;;
        esac
        shift
    done
}

print_banner() {
    echo "=========================================="
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo "AI Model Health Monitoring Script"
    echo "=========================================="
    echo ""
}

cleanup_environment() {
    if [[ -n "${PGPASSWORD:-}" ]]; then
        unset PGPASSWORD
    fi
    log_debug "Environment cleaned up"
}

#######################
# Database Functions
#######################

parse_pgpass_file() {
    local pgpass_file="$HOME/.pgpass"
    
    if [[ ! -f "$pgpass_file" || ! -r "$pgpass_file" ]]; then
        log_error "Cannot read .pgpass file: $pgpass_file"
        return 1
    fi
    
    local line
    line=$(head -n 1 "$pgpass_file")
    
    IFS=':' read -r DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD <<< "$line"
    
    if [[ -z "$DB_HOST" || -z "$DB_PORT" || -z "$DB_NAME" || -z "$DB_USER" || -z "$DB_PASSWORD" ]]; then
        log_error "Invalid .pgpass entry format"
        return 1
    fi
    
    return 0
}

setup_database_connection() {
    export PGPASSWORD="$DB_PASSWORD"
    log_success "Database connection configured for $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
}

execute_query_json() {
    local query="$1"
    local result
    
    log_debug "Executing JSON query: ${query:0:100}..."
    
    result=$(PGPASSWORD="$PGPASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" -U "$DB_USER" \
                 -t -A -c "SELECT json_agg(t) FROM ($query) t;" 2>&1) || {
        log_error "JSON query failed: $result"
        return 1
    }
    
    if [[ "$result" == "NULL" ]]; then
        log_warn "Query returned no rows"
        echo "[]"
        return 0
    fi
    
    log_debug "Query returned JSON data: ${#result} bytes"
    echo "$result"
}

verify_database_schema() {
    local check_query="SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'app' 
        AND table_name = 'queries'
    );"
    
    local result
    result=$(PGPASSWORD="$PGPASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" -U "$DB_USER" \
                 -t -A -c "$check_query" 2>&1) || {
        log_error "Schema check failed: $result"
        return 1
    }
    
    if [[ "$result" != "t" ]]; then
        log_error "Required table app.queries does not exist"
        return 1
    fi
    
    log_success "Database schema verified"
    return 0
}

#######################
# Query Functions
#######################

fetch_monitoring_queries() {
    local sql="SELECT query_ref, query_code FROM app.queries WHERE query_ref IN (51, 52) ORDER BY query_ref"
    local json_result
    
    json_result=$(execute_query_json "$sql") || return 1
    
    if [[ "$json_result" == "[]" ]]; then
        log_error "No monitoring queries found"
        return 1
    fi
    
    QUERY_GET_MODELS=$(echo "$json_result" | jq -r '.[] | select(.query_ref == 51) | .query_code')
    QUERY_UPDATE_MODEL=$(echo "$json_result" | jq -r '.[] | select(.query_ref == 52) | .query_code')
    
    if [[ -z "$QUERY_GET_MODELS" || -z "$QUERY_UPDATE_MODEL" ]]; then
        log_error "Failed to extract required queries"
        return 1
    fi
    
    log_success "Loaded monitoring queries"
    return 0
}

display_monitoring_queries() {
    if [[ $DEBUG -eq 1 ]]; then
        echo "=========================================="
        echo "Query #1 (query_ref: 51) - Get Models:"
        echo "=========================================="
        echo "$QUERY_GET_MODELS"
        echo ""
        
        echo "=========================================="
        echo "Query #2 (query_ref: 52) - Update Model:"
        echo "=========================================="
        echo "$QUERY_UPDATE_MODEL"
        echo ""
    fi
}

#######################
# Model Functions
#######################

clean_json_value() {
    local value="$1"
    # Remove surrounding quotes if present
    echo "$value" | sed 's/^"//;s/"$//'
}

parse_model_json() {
    local model_json="$1"
    local key_idx="$2"
    
    # Parse all fields at once and store in MODELS associative array
    # Using the key_idx as the base key for all fields
    MODELS["${key_idx}_key_idx"]=$(echo "$model_json" | jq -r '.key_idx // ""' | sed 's/^"//;s/"$//')
    MODELS["${key_idx}_value_txt"]=$(echo "$model_json" | jq -r '.value_txt // ""' | sed 's/^"//;s/"$//')
    MODELS["${key_idx}_name"]=$(echo "$model_json" | jq -r '.name // "unnamed"' | sed 's/^"//;s/"$//')
    MODELS["${key_idx}_model"]=$(echo "$model_json" | jq -r '.model // ""' | sed 's/^"//;s/"$//')
    MODELS["${key_idx}_engine"]=$(echo "$model_json" | jq -r '.engine // "unknown"' | sed 's/^"//;s/"$//')
    MODELS["${key_idx}_endpoint"]=$(echo "$model_json" | jq -r '.endpoint // ""' | sed 's/^"//;s/"$//')
    MODELS["${key_idx}_apikey"]=$(echo "$model_json" | jq -r '.apikey // ""' | sed 's/^"//;s/"$//')
    MODELS["${key_idx}_orgkey"]=$(echo "$model_json" | jq -r '.orgkey // ""' | sed 's/^"//;s/"$//')
    MODELS["${key_idx}_pinged"]=$(echo "$model_json" | jq -r '.pinged // ""' | sed 's/^"//;s/"$//')
    MODELS["${key_idx}_ponged"]=$(echo "$model_json" | jq -r '.ponged // ""' | sed 's/^"//;s/"$//')
    MODELS["${key_idx}_icon"]=$(echo "$model_json" | jq -r '.icon // "<i class=\"fad fa-robot\"></i>"' | sed 's/^"//;s/"$//')
}

fetch_model_list() {
    log_info "Fetching AI models from database..."
    
    local models_json
    if echo "$QUERY_GET_MODELS" | grep -qi "json_"; then
        log_debug "Query appears to return JSON directly"
        models_json=$(PGPASSWORD="$PGPASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" -U "$DB_USER" \
                     -t -A -c "$QUERY_GET_MODELS" 2>&1) || {
            log_error "Failed to execute model query"
            return 1
        }
    else
        log_debug "Wrapping query in JSON aggregation"
        models_json=$(execute_query_json "$QUERY_GET_MODELS") || {
            log_error "Failed to fetch model list"
            return 1
        }
    fi
    
    log_debug "Raw query result (first 500 chars): ${models_json:0:500}"
    
    if ! echo "$models_json" | jq empty 2>/dev/null; then
        log_error "Invalid JSON returned from models query"
        return 1
    fi
    
    local model_count
    model_count=$(echo "$models_json" | jq 'length')
    
    # Clear and rebuild MODELS array
    MODELS=()
    
    # Store list of key_idx values for iteration
    MODEL_KEYS=""
    
    local i=0
    while [[ $i -lt $model_count ]]; do
        local model_json
        model_json=$(echo "$models_json" | jq -c ".[$i]")
        
        # Get the key_idx for this model
        local key_idx=$(echo "$model_json" | jq -r '.key_idx // ""' | sed 's/^"//;s/"$//')
        
        if [[ -n "$key_idx" ]]; then
            parse_model_json "$model_json" "$key_idx"
            MODEL_KEYS="$MODEL_KEYS $key_idx"
        else
            log_warn "Model missing key_idx, skipping"
        fi
        
        ((i++))
    done
    
    # Trim leading space from MODEL_KEYS
    MODEL_KEYS="${MODEL_KEYS# }"
    
    log_success "Retrieved $model_count AI models from database"
    return 0
}

display_model_summary() {
    if [[ -z "$MODEL_KEYS" ]]; then
        log_warn "No models to display"
        return 0
    fi
    
    echo ""
    echo "=========================================="
    echo "Model Summary:"
    echo "=========================================="
    
    local i=0
    for key_idx in $MODEL_KEYS; do
        ((i++))
        
        local name="${MODELS[${key_idx}_name]}"
        local engine="${MODELS[${key_idx}_engine]}"
        
        if [[ $DEBUG -eq 1 ]]; then
            echo "Model #$i (key_idx: $key_idx):"
            echo "  Name: $name"
            echo "  Engine: $engine"
            echo "  Model: ${MODELS[${key_idx}_model]}"
            echo "  Endpoint: ${MODELS[${key_idx}_endpoint]}"
            echo "  Pinged: ${MODELS[${key_idx}_pinged]}"
            echo "  Ponged: ${MODELS[${key_idx}_ponged]}"
            echo ""
        else
            echo "Model #$i: $name ($engine)"
        fi
    done
    
    echo ""
    echo "Total models: $i"
    echo ""
}

#######################
# Model Checking Functions
#######################

validate_endpoint() {
    local endpoint="$1"
    
    # Basic URL validation
    if [[ ! "$endpoint" =~ ^https?:// ]]; then
        log_warn "Invalid endpoint format: $endpoint"
        return 1
    fi
    
    return 0
}

update_model_timestamp() {
    local key_idx="$1"
    local field="$2"  # "Pinged" or "Ponged"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log_debug "[DRY RUN] Would update $field for model $key_idx"
        return 0
    fi
    
    # Validate field parameter
    if [[ "$field" != "Pinged" && "$field" != "Ponged" ]]; then
        log_error "Invalid field parameter: $field (must be 'Pinged' or 'Ponged')"
        return 1
    fi
    
    log_debug "Updating $field timestamp for model $key_idx"
    
    # Use the QUERY_UPDATE_MODEL that was loaded from the database
    # Replace parameters with actual values
    local update_query="${QUERY_UPDATE_MODEL}"
    update_query="${update_query//:KEY_IDX/$key_idx}"
    update_query="${update_query//:JSON_PATH/\'$field\'}"  # Add quotes around the field

    
    # Execute the update query
    local result
    result=$(PGPASSWORD="$PGPASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" -U "$DB_USER" \
                 -t -A -c "$update_query" 2>&1) || {
        log_error "Failed to update $field for model $key_idx: $result"
        return 1
    }
    
    # Check if update was successful (PostgreSQL returns "UPDATE 1" for one row updated)
    if [[ "$result" == "UPDATE 1" ]]; then
        log_debug "Successfully updated $field timestamp for model $key_idx"
        return 0
    else
        log_warn "Unexpected update result for model $key_idx: $result"
        return 1
    fi
}

ping_xAI_model() {
    local key_idx="$1"
    local response_file="/tmp/model_check_$$.json"
    local http_code
    
    # Get model data from our pre-parsed MODELS array
    local name="${MODELS[${key_idx}_name]}"
    local model="${MODELS[${key_idx}_model]}"
    local endpoint="${MODELS[${key_idx}_endpoint]}"
    local apikey="${MODELS[${key_idx}_apikey]}"
    
    log_debug "Checking xAI model: $name (model: $model)"
    
    # Validate endpoint
    if ! validate_endpoint "$endpoint"; then
        MODEL_CHECK_RESULTS["$key_idx"]="Invalid Endpoint"
        update_model_timestamp "$key_idx" "Pinged" || log_warn "Failed to update Pinged timestamp"
        return 1
    fi
    
    # Prepare the ping request
    local request_body=$(jq -n \
        --arg model "$model" \
        '{
            model: $model,
            messages: [{role: "user", content: "ping"}],
            max_tokens: 10,
            temperature: 0
        }')
    
    # Send the request
    log_debug "Sending ping to $endpoint"
    http_code=$(curl -s -w "%{http_code}" -o "$response_file" \
        --max-time 30 \
        -H "Authorization: Bearer $apikey" \
        -H "Content-Type: application/json" \
        -d "$request_body" \
        "$endpoint" 2>/dev/null) || {
        MODEL_CHECK_RESULTS["$key_idx"]="Network Error"
        update_model_timestamp "$key_idx" "Pinged" || log_warn "Failed to update Pinged timestamp"
        rm -f "$response_file"
        return 1
    }
    
    # Check HTTP response code
    if [[ "$http_code" != "200" ]]; then
        log_warn "HTTP error $http_code for model $name"
        MODEL_CHECK_RESULTS["$key_idx"]="HTTP Error $http_code"
        update_model_timestamp "$key_idx" "Pinged" || log_warn "Failed to update Pinged timestamp"
        rm -f "$response_file"
        return 1
    fi
    
    # Parse response
    local response_text=""
    local success=0
    
    if [[ -f "$response_file" ]]; then
        response_text=$(jq -r '.choices[0].message.content // ""' "$response_file" 2>/dev/null)
        
        if [[ -n "$response_text" ]]; then
            log_success "Model $name responded: $response_text"
            MODEL_CHECK_RESULTS["$key_idx"]="$response_text"
            success=1
        else
            log_error "Invalid response format from $name"
            MODEL_CHECK_RESULTS["$key_idx"]="Invalid Response"
        fi
    fi
    
    # Update the appropriate timestamp based on success/failure
    if [[ $success -eq 1 ]]; then
        update_model_timestamp "$key_idx" "Ponged" || log_warn "Failed to update Ponged timestamp"
    else
        update_model_timestamp "$key_idx" "Pinged" || log_warn "Failed to update Pinged timestamp"
    fi
    
    rm -f "$response_file"
    return 0
}

ping_OpenAI_model() {
    local key_idx="$1"
    local response_file="/tmp/model_check_$$.json"
    local http_code
    
    # Get model data from our pre-parsed MODELS array
    local name="${MODELS[${key_idx}_name]}"
    local model="${MODELS[${key_idx}_model]}"
    local endpoint="${MODELS[${key_idx}_endpoint]}"
    local apikey="${MODELS[${key_idx}_apikey]}"
    local orgkey="${MODELS[${key_idx}_orgkey]}"
    
    log_debug "Checking OpenAI model: $name (model: $model)"
    
    # Validate endpoint
    if ! validate_endpoint "$endpoint"; then
        MODEL_CHECK_RESULTS["$key_idx"]="Invalid Endpoint"
        update_model_timestamp "$key_idx" "Pinged" || log_warn "Failed to update Pinged timestamp"
        return 1
    fi
    
    # Prepare the ping request
    local request_body=$(jq -n \
        --arg model "$model" \
        '{
            model: $model,
            messages: [{role: "user", content: "ping"}],
            max_tokens: 10,
            temperature: 0
        }')
    
    # Build curl command with optional organization header
    local curl_opts=(
        -s -w "%{http_code}" -o "$response_file"
        --max-time 30
        -H "Authorization: Bearer $apikey"
        -H "Content-Type: application/json"
    )
    
    # Add organization header if present
    if [[ -n "$orgkey" ]]; then
        curl_opts+=(-H "OpenAI-Organization: $orgkey")
    fi
    
    curl_opts+=(-d "$request_body" "$endpoint")
    
    # Send the request
    log_debug "Sending ping to $endpoint"
    http_code=$(curl "${curl_opts[@]}" 2>/dev/null) || {
        MODEL_CHECK_RESULTS["$key_idx"]="Network Error"
        update_model_timestamp "$key_idx" "Pinged" || log_warn "Failed to update Pinged timestamp"
        rm -f "$response_file"
        return 1
    }
    
    # Check HTTP response code
    if [[ "$http_code" != "200" ]]; then
        log_warn "HTTP error $http_code for model $name"
        MODEL_CHECK_RESULTS["$key_idx"]="HTTP Error $http_code"
        update_model_timestamp "$key_idx" "Pinged" || log_warn "Failed to update Pinged timestamp"
        rm -f "$response_file"
        return 1
    fi
    
    # Parse response (same format as xAI)
    local response_text=""
    local success=0
    
    if [[ -f "$response_file" ]]; then
        response_text=$(jq -r '.choices[0].message.content // ""' "$response_file" 2>/dev/null)
        
        if [[ -n "$response_text" ]]; then
            log_success "Model $name responded: $response_text"
            MODEL_CHECK_RESULTS["$key_idx"]="$response_text"
            success=1
        else
            log_error "Invalid response format from $name"
            MODEL_CHECK_RESULTS["$key_idx"]="Invalid Response"
        fi
    fi
    
    # Update the appropriate timestamp based on success/failure
    if [[ $success -eq 1 ]]; then
        update_model_timestamp "$key_idx" "Ponged" || log_warn "Failed to update Ponged timestamp"
    else
        update_model_timestamp "$key_idx" "Pinged" || log_warn "Failed to update Pinged timestamp"
    fi
    
    rm -f "$response_file"
    return 0
}

ping_Anthropic_model() {
    local key_idx="$1"
    local response_file="/tmp/model_check_$$.json"
    local http_code
    
    # Get model data from our pre-parsed MODELS array
    local name="${MODELS[${key_idx}_name]}"
    local model="${MODELS[${key_idx}_model]}"
    local endpoint="${MODELS[${key_idx}_endpoint]}"
    local apikey="${MODELS[${key_idx}_apikey]}"
    
    log_debug "Checking Anthropic model: $name (model: $model)"
    
    # Validate endpoint
    if ! validate_endpoint "$endpoint"; then
        MODEL_CHECK_RESULTS["$key_idx"]="Invalid Endpoint"
        update_model_timestamp "$key_idx" "Pinged" || log_warn "Failed to update Pinged timestamp"
        return 1
    fi
    
    # Prepare the ping request (Anthropic format)
    local request_body=$(jq -n \
        --arg model "$model" \
        '{
            model: $model,
            max_tokens: 10,
            messages: [{role: "user", content: "ping"}]
        }')
    
    # Send the request
    log_debug "Sending ping to $endpoint"
    http_code=$(curl -s -w "%{http_code}" -o "$response_file" \
        --max-time 30 \
        -H "x-api-key: $apikey" \
        -H "Content-Type: application/json" \
        -H "anthropic-version: 2023-06-01" \
        -d "$request_body" \
        "$endpoint" 2>/dev/null) || {
        MODEL_CHECK_RESULTS["$key_idx"]="Network Error"
        update_model_timestamp "$key_idx" "Pinged" || log_warn "Failed to update Pinged timestamp"
        rm -f "$response_file"
        return 1
    }
    
    # Check HTTP response code
    if [[ "$http_code" != "200" ]]; then
        log_warn "HTTP error $http_code for model $name"
        MODEL_CHECK_RESULTS["$key_idx"]="HTTP Error $http_code"
        update_model_timestamp "$key_idx" "Pinged" || log_warn "Failed to update Pinged timestamp"
        rm -f "$response_file"
        return 1
    fi
    
    # Parse response (Anthropic format)
    local response_text=""
    local success=0
    
    if [[ -f "$response_file" ]]; then
        # Anthropic returns content in a different structure
        response_text=$(jq -r '.content[0].text // ""' "$response_file" 2>/dev/null)
        
        if [[ -n "$response_text" ]]; then
            log_success "Model $name responded: $response_text"
            MODEL_CHECK_RESULTS["$key_idx"]="$response_text"
            success=1
        else
            log_error "Invalid response format from $name"
            MODEL_CHECK_RESULTS["$key_idx"]="Invalid Response"
        fi
    fi
    
    # Update the appropriate timestamp based on success/failure
    if [[ $success -eq 1 ]]; then
        update_model_timestamp "$key_idx" "Ponged" || log_warn "Failed to update Ponged timestamp"
    else
        update_model_timestamp "$key_idx" "Pinged" || log_warn "Failed to update Pinged timestamp"
    fi
    
    rm -f "$response_file"
    return 0
}

ping_Ollama_model() {
    local key_idx="$1"
    local response_file="/tmp/model_check_$$.json"
    local http_code
    
    # Get model data from our pre-parsed MODELS array
    local name="${MODELS[${key_idx}_name]}"
    local model="${MODELS[${key_idx}_model]}"
    local endpoint="${MODELS[${key_idx}_endpoint]}"
    
    log_debug "Checking Ollama model: $name (model: $model)"
    
    # Validate endpoint
    if ! validate_endpoint "$endpoint"; then
        MODEL_CHECK_RESULTS["$key_idx"]="Invalid Endpoint"
        update_model_timestamp "$key_idx" "Pinged" || log_warn "Failed to update Pinged timestamp"
        return 1
    fi
    
    # Ollama can support two formats - try OpenAI compatibility first
    local use_openai_format=0
    if [[ "$endpoint" =~ /v1/chat/completions$ ]]; then
        use_openai_format=1
    fi
    
    local request_body
    if [[ $use_openai_format -eq 1 ]]; then
        # OpenAI-compatible format
        request_body=$(jq -n \
            --arg model "$model" \
            '{
                model: $model,
                messages: [{role: "user", content: "ping"}],
                max_tokens: 10,
                temperature: 0,
                stream: false
            }')
    else
        # Native Ollama format
        request_body=$(jq -n \
            --arg model "$model" \
            '{
                model: $model,
                prompt: "ping",
                stream: false
            }')
    fi
    
    # Send the request
    log_debug "Sending ping to $endpoint"
    http_code=$(curl -s -w "%{http_code}" -o "$response_file" \
        --max-time 30 \
        -H "Content-Type: application/json" \
        -d "$request_body" \
        "$endpoint" 2>/dev/null) || {
        MODEL_CHECK_RESULTS["$key_idx"]="Network Error"
        update_model_timestamp "$key_idx" "Pinged" || log_warn "Failed to update Pinged timestamp"
        rm -f "$response_file"
        return 1
    }
    
    # Check HTTP response code
    if [[ "$http_code" != "200" ]]; then
        log_warn "HTTP error $http_code for model $name"
        MODEL_CHECK_RESULTS["$key_idx"]="HTTP Error $http_code"
        update_model_timestamp "$key_idx" "Pinged" || log_warn "Failed to update Pinged timestamp"
        rm -f "$response_file"
        return 1
    fi
    
    # Parse response based on format
    local response_text=""
    local success=0
    
    if [[ -f "$response_file" ]]; then
        if [[ $use_openai_format -eq 1 ]]; then
            # OpenAI format
            response_text=$(jq -r '.choices[0].message.content // ""' "$response_file" 2>/dev/null)
        else
            # Native Ollama format
            response_text=$(jq -r '.response // ""' "$response_file" 2>/dev/null)
        fi
        
        if [[ -n "$response_text" ]]; then
            log_success "Model $name responded: $response_text"
            MODEL_CHECK_RESULTS["$key_idx"]="$response_text"
            success=1
        else
            log_error "Invalid response format from $name"
            MODEL_CHECK_RESULTS["$key_idx"]="Invalid Response"
        fi
    fi
    
    # Update the appropriate timestamp based on success/failure
    if [[ $success -eq 1 ]]; then
        update_model_timestamp "$key_idx" "Ponged" || log_warn "Failed to update Ponged timestamp"
    else
        update_model_timestamp "$key_idx" "Pinged" || log_warn "Failed to update Pinged timestamp"
    fi
    
    rm -f "$response_file"
    return 0
}

check_model_status() {
    log_info "Starting model status checks..."
    
    # Clear previous results
    MODEL_CHECK_RESULTS=()
    
    for key_idx in $MODEL_KEYS; do
        local engine="${MODELS[${key_idx}_engine]}"
        local name="${MODELS[${key_idx}_name]}"
        
        log_info "Checking model: $name (engine: $engine)"
        
        case "$engine" in
            "xAI")
                ping_xAI_model "$key_idx" ;;
            "OpenAI")
                ping_OpenAI_model "$key_idx" ;;
            "Anthropic")
                ping_Anthropic_model "$key_idx" ;;
            "Ollama")
                ping_Ollama_model "$key_idx" ;;
            *)
                log_warn "Unknown engine type: $engine"
                MODEL_CHECK_RESULTS["$key_idx"]="Unknown Engine"
                ;;
        esac
    done
    
    # Display results summary
    display_check_results
}

display_check_results() {
    echo ""
    echo "=========================================="
    echo "Model Check Results:"
    echo "=========================================="
    
    for key_idx in $MODEL_KEYS; do
        local result="${MODEL_CHECK_RESULTS[$key_idx]:-No Result}"
        local name="${MODELS[${key_idx}_name]}"
        
        # Success: Any non-error response (not HTTP Error, Network Error, etc.)
        if [[ ! "$result" =~ ^(HTTP\ Error|Network\ Error|Invalid\ |Unknown\ |Not\ Implemented|No\ Result) ]]; then
            echo -e "${COLOR_GREEN}✓${COLOR_RESET} $name: $result"
        else
            echo -e "${COLOR_RED}✗${COLOR_RESET} $name: $result"
        fi
    done
    
    echo ""
}

#######################
# Orchestration Functions
#######################

initialize_monitoring_system() {
    parse_pgpass_file || {
        log_error "Failed to read database credentials"
        return 1
    }
    
    setup_database_connection
    verify_database_schema || return 1
    
    log_success "Monitoring system initialized"
    return 0
}

load_monitoring_configuration() {
    fetch_monitoring_queries || {
        log_error "Failed to load monitoring queries"
        return 1
    }
    
    display_monitoring_queries
    log_success "Monitoring configuration loaded"
    return 0
}

discover_ai_models() {
    fetch_model_list || {
        log_error "Failed to discover AI models"
        return 1
    }
    
    display_model_summary
    log_success "AI models discovered"
    return 0
}

update_model_statuses() {
    log_info "Database timestamp updates completed during model checks"
    return 0
}

notify_homeassistant() {
    log_info "Sending model status updates to HomeAssistant..."

    # Load HA configuration from environment
    local ha_url="${HA_URL:-http://localhost:8123}"
    local ha_token="${HA_TOKEN:-}"

    # Check if token is available
    if [[ -z "$ha_token" ]]; then
        log_error "No HomeAssistant token found in HA_TOKEN"
        return 1
    fi

    # Make sure the URL ends with /api
    if [[ ! "$ha_url" =~ /api$ ]]; then
        ha_url="${ha_url%/}/api"
    fi

    log_debug "HomeAssistant API URL: $ha_url"

    # Create or update individual entities for each model
    local success_count=0
    local failure_count=0

    for key_idx in $MODEL_KEYS; do
        local name="${MODELS[${key_idx}_name]}"
        local engine="${MODELS[${key_idx}_engine]}"
        local model="${MODELS[${key_idx}_model]}"
        local icon="${MODELS[${key_idx}_icon]:-<i class=\"fad fa-robot\"></i>}"
        local result="${MODEL_CHECK_RESULTS[$key_idx]:-Unknown}"
        local pinged="${MODELS[${key_idx}_pinged]}"
        local ponged="${MODELS[${key_idx}_ponged]}"

        # Determine status based on result
        local status="unknown"
        if [[ ! "$result" =~ ^(HTTP\ Error|Network\ Error|Invalid\ |Unknown\ |Not\ Implemented|No\ Result) ]]; then
            status="online"
        else
            status="offline"
        fi

        # Create entity_id using key_idx for uniqueness
        local entity_id="sensor.ai_model_${key_idx}"

        # Create payload for model sensor
        local payload=$(jq -n \
            --arg state "$status" \
            --arg name "$name" \
            --arg engine "$engine" \
            --arg model "$model" \
            --arg result "$result" \
            --arg icon "$icon" \
            --arg pinged "$pinged" \
            --arg ponged "$ponged" \
            --arg key_idx "$key_idx" \
            '{
                state: $state,
                attributes: {
                    friendly_name: $name,
                    device_class: "connectivity",
                    state_class: "measurement",
                    icon: "mdi:robot",
                    engine: $engine,
                    model: $model,
                    last_result: $result,
                    last_pinged: $pinged,
                    last_ponged: $ponged,
                    key_idx: $key_idx,
                    html_icon: $icon
                }
            }')

        # Send update to HomeAssistant
        if [[ $DRY_RUN -eq 0 ]]; then
            log_debug "Updating HomeAssistant entity: $entity_id"

            local http_code
            http_code=$(curl -s -w "%{http_code}" -o /dev/null \
                --max-time 10 \
                -H "Authorization: Bearer $ha_token" \
                -H "Content-Type: application/json" \
                -X POST \
                -d "$payload" \
                "$ha_url/states/$entity_id" 2>/dev/null) || {
                log_error "Failed to update entity: $entity_id"
                ((failure_count++))
                continue
            }

            if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
                log_debug "Successfully updated entity $entity_id: $status"
                ((success_count++))
            else
                log_error "Failed to update entity $entity_id: HTTP $http_code"
                ((failure_count++))
            fi
        else
            log_debug "[DRY RUN] Would update HA entity: $entity_id = $status"
            ((success_count++))
        fi
    done

    # Also update a summary entity
    if [[ $success_count -gt 0 || $DRY_RUN -eq 1 ]]; then
        local online_count=0
        local total_count=${#MODEL_KEYS}

        for key_idx in $MODEL_KEYS; do
            local result="${MODEL_CHECK_RESULTS[$key_idx]:-Unknown}"
            if [[ ! "$result" =~ ^(HTTP\ Error|Network\ Error|Invalid\ |Unknown\ |Not\ Implemented|No\ Result) ]]; then
                ((online_count++))
            fi
        done

        local overall_status="unknown"
        if [[ $online_count -eq $total_count && $total_count -gt 0 ]]; then
            overall_status="online"
        elif [[ $online_count -eq 0 && $total_count -gt 0 ]]; then
            overall_status="offline"
        elif [[ $online_count -gt 0 && $online_count -lt $total_count ]]; then
            overall_status="degraded"
        fi

        local summary_payload=$(jq -n \
            --arg state "$overall_status" \
            --arg online "$online_count" \
            --arg total "$total_count" \
            '{
                state: $state,
                attributes: {
                    friendly_name: "AI Models Status Summary",
                    device_class: "connectivity",
                    state_class: "measurement",
                    icon: "mdi:brain",
                    online_count: $online,
                    total_count: $total,
                    last_updated: "'$(date -Iseconds)'"
                }
            }')

        if [[ $DRY_RUN -eq 0 ]]; then
            local summary_entity="sensor.ai_models_summary"
            log_debug "Updating summary entity: $summary_entity"

            local http_code
            http_code=$(curl -s -w "%{http_code}" -o /dev/null \
                --max-time 10 \
                -H "Authorization: Bearer $ha_token" \
                -H "Content-Type: application/json" \
                -X POST \
                -d "$summary_payload" \
                "$ha_url/states/$summary_entity" 2>/dev/null) || {
                log_error "Failed to update summary entity"
            }

            if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
                log_debug "Successfully updated summary entity: $overall_status"
            else
                log_error "Failed to update summary entity: HTTP $http_code"
            fi
        else
            log_debug "[DRY RUN] Would update summary entity: ai_models_summary = $overall_status"
        fi
    fi

    log_success "HomeAssistant notifications completed: $success_count successes, $failure_count failures"
    return 0
}

#######################
# Main Function
#######################

main() {
    print_banner
    log_info "Starting AI model health monitoring"
    
    initialize_monitoring_system || exit 1
    load_monitoring_configuration || exit 1
    discover_ai_models || exit 1
    check_model_status || exit 1
    update_model_statuses || exit 1
    notify_homeassistant || exit 1
    
    log_success "Model health check completed successfully"
}

# Set up cleanup trap
trap cleanup_environment EXIT

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    
    if [[ $DEBUG -eq 1 ]]; then
        set -x
    fi
    
    main
fi
