#!/usr/bin/env bash

# =============================================================================
# tables.sh - Library for JSON to ANSI tables
# Section 01: Initial Setup, Declarations, and Color Handling
# =============================================================================
# This section handles the basic setup including global variable declarations,
# datatype handlers, theme configuration, and color code definitions.
# =============================================================================

# -----------------------------------------------------------------------------
# Global Configuration Variables
# -----------------------------------------------------------------------------
# These variables control the overall behavior of the table rendering system

# COLUMN_COUNT: Number of columns in the current table
declare -g COLUMN_COUNT=0

# MAX_LINES: Maximum number of lines in any single row (for multi-line content)
declare -g MAX_LINES=1

# THEME_NAME: Current theme name (Red, Blue, etc.)
declare -g THEME_NAME="Red"

# DEFAULT_PADDING: Default padding around cell content
declare -g DEFAULT_PADDING=1

# -----------------------------------------------------------------------------
# Datatype Handler Registry
# -----------------------------------------------------------------------------
# This associative array maps datatype operations to their corresponding functions.
# Each datatype (text, int, num, float, kcpu, kmem) has three operations:
# - _validate: Function to validate values of this type
# - _format: Function to format values for display
# - _summary_types: Space-separated list of supported summary operations

declare -A DATATYPE_HANDLERS=(
    # Text datatype handlers
    [text_validate]="validate_text"
    [text_format]="format_text"
    [text_summary_types]="count unique"
    
    # Integer datatype handlers
    [int_validate]="validate_number"
    [int_format]="format_number"
    [int_summary_types]="sum min max avg count unique"
    
    # Numeric datatype handlers (alias for int with different formatting)
    [num_validate]="validate_number"
    [num_format]="format_num"
    [num_summary_types]="sum min max avg count unique"
    
    # Float datatype handlers
    [float_validate]="validate_number"
    [float_format]="format_float"
    [float_summary_types]="sum min max avg count unique"
    
    # Kubernetes CPU datatype handlers (e.g., "100m" for millicores)
    [kcpu_validate]="validate_kcpu"
    [kcpu_format]="format_kcpu"
    [kcpu_summary_types]="sum min max avg count unique"
    
    # Kubernetes memory datatype handlers (e.g., "256Mi", "1Gi")
    [kmem_validate]="validate_kmem"
    [kmem_format]="format_kmem"
    [kmem_summary_types]="sum min max avg count unique"
)

# -----------------------------------------------------------------------------
# Theme Configuration
# -----------------------------------------------------------------------------
# Global associative array to hold the current theme's configuration
# This will be populated by the get_theme() function
declare -A THEME

# -----------------------------------------------------------------------------
# ANSI Color Code Definitions
# -----------------------------------------------------------------------------
# Define color codes only if they haven't been set already
# This prevents "readonly variable" errors if the script is sourced multiple times

if [[ -z "${RED:-}" ]]; then
    # Basic colors
    declare -r RED='\033[0;31m'        # Red text
    declare -r BLUE='\033[0;34m'       # Blue text
    declare -r GREEN='\033[0;32m'      # Green text
    declare -r YELLOW='\033[0;33m'     # Yellow text
    declare -r CYAN='\033[0;36m'       # Cyan text
    declare -r MAGENTA='\033[0;35m'    # Magenta text
    
    # Text formatting
    declare -r BOLD='\033[1m'          # Bold text
    declare -r DIM='\033[2m'           # Dim text
    declare -r UNDERLINE='\033[4m'     # Underlined text
    
    # Reset codes
    declare -r NC='\033[0m'            # No Color (reset)
fi

# -----------------------------------------------------------------------------
# Color Placeholder Replacement Function
# -----------------------------------------------------------------------------
# This function replaces color placeholders in text with actual ANSI codes.
# Placeholders use the format {COLOR_NAME} and are replaced with the 
# corresponding ANSI escape sequences.
#
# Parameters:
#   $1 - Text containing color placeholders
#
# Returns:
#   Text with placeholders replaced by ANSI color codes
# -----------------------------------------------------------------------------

replace_color_placeholders() {
    local text="$1"
    
    # Replace each color placeholder with its corresponding ANSI code
    text="${text//\{RED\}/$RED}"
    text="${text//\{BLUE\}/$BLUE}"
    text="${text//\{GREEN\}/$GREEN}"
    text="${text//\{YELLOW\}/$YELLOW}"
    text="${text//\{CYAN\}/$CYAN}"
    text="${text//\{MAGENTA\}/$MAGENTA}"
    text="${text//\{BOLD\}/$BOLD}"
    text="${text//\{DIM\}/$DIM}"
    text="${text//\{UNDERLINE\}/$UNDERLINE}"
    text="${text//\{NC\}/$NC}"
    text="${text//\{RESET\}/$NC}"  # RESET is an alias for NC
    
    echo "$text"
}

# =============================================================================
# tables.sh - Library for JSON to ANSI tables
# Section 02: Display Length Calculation Functions
# =============================================================================
# This section handles the complex task of calculating the visual display width
# of text strings, accounting for ANSI escape sequences, Unicode characters,
# and multi-byte character encodings.
# =============================================================================

# -----------------------------------------------------------------------------
# Display Length Calculation Function
# -----------------------------------------------------------------------------
# This is one of the most complex functions in the library. It calculates the
# actual visual width of a string when displayed in a terminal, which is
# crucial for proper table alignment.
#
# The function handles several challenging cases:
# 1. ANSI escape sequences (colors, formatting) - these take up no visual space
# 2. ASCII characters - each takes 1 display unit
# 3. Unicode characters - some take 1 unit, others take 2 (wide characters)
# 4. Multi-byte UTF-8 sequences
#
# Parameters:
#   $1 - The text string to measure
#
# Returns:
#   The visual display width as an integer
# -----------------------------------------------------------------------------

get_display_length() {
    local text="$1"
    local clean_text
    
    # Step 1: Remove ANSI escape sequences
    # These sequences control colors and formatting but don't take visual space
    # Pattern: \x1B\[[0-9;]*[a-zA-Z] matches ANSI escape sequences
    clean_text=$(echo -n "$text" | sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g')
    
    # Step 2: Quick check for pure ASCII text
    # If the text contains only ASCII characters, we can use simple length calculation
    if [[ "$clean_text" =~ ^[[:ascii:]]*$ ]]; then
        echo "${#clean_text}"
        return
    fi
    
    # Step 3: Double-check for non-ASCII characters
    # This is a redundant check to ensure we really need complex Unicode handling
    if [[ ! "$clean_text" =~ [^\x00-\x7F] ]]; then
        echo "${#clean_text}"
        return
    fi
    
    # Step 4: Complex Unicode handling
    # For text containing Unicode characters, we need to analyze each byte
    local codepoints
    
    # Convert text to hexadecimal representation for byte-by-byte analysis
    codepoints=$(echo -n "$clean_text" | od -An -tx1 | tr -d ' \n')
    
    local width=0          # Running total of display width
    local i=0              # Current position in hex string
    local len=${#codepoints}  # Total length of hex string
    
    # Process each byte sequence
    while [[ $i -lt $len ]]; do
        # Extract the first byte of the current character
        local byte1_hex="${codepoints:$i:2}"
        local byte1=$((0x$byte1_hex))
        
        # Determine character type and width based on first byte
        if [[ $byte1 -lt 128 ]]; then
            # ASCII character (0xxxxxxx) - always 1 display unit
            ((width++))
            ((i += 2))  # Move to next byte (2 hex chars = 1 byte)
            
        elif [[ $byte1 -lt 224 ]]; then
            # 2-byte UTF-8 sequence (110xxxxx 10xxxxxx)
            if [[ $((i + 4)) -le $len ]]; then
                local byte2_hex="${codepoints:$((i+2)):2}"
                
                # Decode the Unicode codepoint
                local codepoint=$(( (byte1 & 0x1F) << 6 | (0x$byte2_hex & 0x3F) ))
                
                # Check if this is a wide character (takes 2 display units)
                # Range 4352-55215 includes many CJK characters
                if [[ $codepoint -ge 4352 && $codepoint -le 55215 ]]; then
                    ((width += 2))
                else
                    ((width++))
                fi
                ((i += 4))  # Skip both bytes of the sequence
            else
                # Incomplete sequence - treat as single width
                ((width++))
                ((i += 2))
            fi
            
        elif [[ $byte1 -lt 240 ]]; then
            # 3-byte UTF-8 sequence (1110xxxx 10xxxxxx 10xxxxxx)
            if [[ $((i + 6)) -le $len ]]; then
                local byte2_hex="${codepoints:$((i+2)):2}"
                local byte3_hex="${codepoints:$((i+4)):2}"
                
                # Decode the Unicode codepoint
                local codepoint=$(( (byte1 & 0x0F) << 12 | (0x$byte2_hex & 0x3F) << 6 | (0x$byte3_hex & 0x3F) ))
                
                # Check for emoji and other wide characters
                # Ranges 127744-129535 and 9728-9983 include many emoji
                if [[ $codepoint -ge 127744 && $codepoint -le 129535 ]] || [[ $codepoint -ge 9728 && $codepoint -le 9983 ]]; then
                    ((width += 2))
                else
                    ((width++))
                fi
                ((i += 6))  # Skip all three bytes
            else
                # Incomplete sequence - treat as single width
                ((width++))
                ((i += 2))
            fi
            
        else
            # 4-byte UTF-8 sequence (11110xxx 10xxxxxx 10xxxxxx 10xxxxxx)
            if [[ $((i + 8)) -le $len ]]; then
                # Most 4-byte sequences are wide characters (emoji, etc.)
                ((width += 2))
                ((i += 8))  # Skip all four bytes
            else
                # Incomplete sequence - treat as single width
                ((width++))
                ((i += 2))
            fi
        fi
    done
    
    echo "$width"
}

# =============================================================================
# tables.sh - Library for JSON to ANSI tables
# Section 03: Data Formatting Functions
# =============================================================================
# This section contains all the functions responsible for formatting different
# types of data for display in table cells. It includes validation functions,
# number formatting with commas, text wrapping, and specialized formatters for
# Kubernetes resource units (CPU and memory).
# =============================================================================

# -----------------------------------------------------------------------------
# Number Formatting with Thousands Separators
# -----------------------------------------------------------------------------
# Adds comma separators to numbers for better readability.
# Handles both integer and decimal numbers.
#
# Parameters:
#   $1 - The number to format
#
# Returns:
#   The number with comma separators (e.g., "1234567" -> "1,234,567")
# -----------------------------------------------------------------------------

format_with_commas() {
    local num="$1"
    
    # Handle decimal numbers by separating integer and decimal parts
    if [[ "$num" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
        local integer_part="${BASH_REMATCH[1]}"
        local decimal_part="${BASH_REMATCH[2]}"
        
        # Add commas to integer part using regex replacement
        local result="$integer_part"
        while [[ $result =~ ^([0-9]+)([0-9]{3}.*) ]]; do
            result="${BASH_REMATCH[1]},${BASH_REMATCH[2]}"
        done
        
        echo "${result}.${decimal_part}"
    else
        # Handle integer numbers
        local result="$num"
        while [[ $result =~ ^([0-9]+)([0-9]{3}.*) ]]; do
            result="${BASH_REMATCH[1]},${BASH_REMATCH[2]}"
        done
        echo "$result"
    fi
}

# -----------------------------------------------------------------------------
# Data Validation Functions
# -----------------------------------------------------------------------------
# These functions validate input data according to their expected types.
# They return the validated value or an empty string if invalid.
# -----------------------------------------------------------------------------

# Generic validation function that handles multiple data types
validate_data() {
    local value="$1"
    local type="$2"
    
    case "$type" in
        text)
            # Text is valid if it's not null
            [[ "$value" != "null" ]] && echo "$value" || echo ""
            ;;
            
        number|int|float|num)
            # Numbers must match numeric pattern or be null/zero
            [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ || "$value" == "0" || "$value" == "null" ]] && echo "$value" || echo ""
            ;;
            
        kcpu)
            # Kubernetes CPU: millicores (100m) or decimal values
            [[ "$value" =~ ^[0-9]+m$ || "$value" == "0" || "$value" == "0m" || "$value" == "null" || "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]] && echo "$value" || echo "$value"
            ;;
            
        kmem)
            # Kubernetes memory: K/M/G suffixes or binary suffixes (Ki/Mi/Gi)
            [[ "$value" =~ ^[0-9]+[KMG]$ || "$value" =~ ^[0-9]+Mi$ || "$value" =~ ^[0-9]+Gi$ || "$value" =~ ^[0-9]+Ki$ || "$value" == "0" || "$value" == "null" ]] && echo "$value" || echo "$value"
            ;;
            
        *)
            # Unknown types pass through unchanged
            echo "$value"
            ;;
    esac
}

# Specific validation functions for each data type
validate_text() {
    validate_data "$1" "text"
}

validate_number() {
    validate_data "$1" "number"
}

validate_kcpu() {
    validate_data "$1" "kcpu"
}

validate_kmem() {
    validate_data "$1" "kmem"
}

# -----------------------------------------------------------------------------
# Text Formatting Function
# -----------------------------------------------------------------------------
# Formats text values with support for length limits, wrapping, and justification.
#
# Parameters:
#   $1 - value: The text value to format
#   $2 - format: Format specification (currently unused)
#   $3 - string_limit: Maximum length (0 = no limit)
#   $4 - wrap_mode: "wrap" or "clip"
#   $5 - wrap_char: Character to split on when wrapping
#   $6 - justification: "left", "right", or "center"
#
# Returns:
#   Formatted text according to the specified parameters
# -----------------------------------------------------------------------------

format_text() {
    local value="$1"
    local format="$2"
    local string_limit="$3"
    local wrap_mode="$4"
    local wrap_char="$5"
    local justification="$6"
    
    # Handle null or empty values
    [[ -z "$value" || "$value" == "null" ]] && {
        echo ""
        return
    }
    
    # Apply string length limit if specified
    if [[ "$string_limit" -gt 0 && ${#value} -gt $string_limit ]]; then
        if [[ "$wrap_mode" == "wrap" && -n "$wrap_char" ]]; then
            # Wrap on specific character
            local wrapped=""
            local IFS="$wrap_char"
            read -ra parts <<< "$value"
            
            for part in "${parts[@]}"; do
                wrapped+="$part\n"
            done
            
            # Limit number of lines based on string_limit
            echo -e "$wrapped" | head -n $((string_limit / ${#wrap_char}))
            
        elif [[ "$wrap_mode" == "wrap" ]]; then
            # Simple truncation for wrap mode without wrap_char
            echo "${value:0:$string_limit}"
        else
            # Clip mode with justification
            case "$justification" in
                "right")
                    echo "${value: -${string_limit}}"
                    ;;
                "center")
                    local start=$(( (${#value} - string_limit) / 2 ))
                    echo "${value:${start}:${string_limit}}"
                    ;;
                *)
                    echo "${value:0:$string_limit}"
                    ;;
            esac
        fi
    else
        # No length limit - return value as-is
        echo "$value"
    fi
}

# -----------------------------------------------------------------------------
# Numeric Formatting Functions
# -----------------------------------------------------------------------------
# These functions format numeric values with optional comma separators.
# -----------------------------------------------------------------------------

# Generic numeric formatter
format_numeric() {
    local value="$1"
    local format="$2"
    local use_commas="$3"
    
    # Handle null, empty, or zero values
    [[ -z "$value" || "$value" == "null" || "$value" == "0" ]] && {
        echo ""
        return
    }
    
    # Format valid numbers
    if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        if [[ -n "$format" ]]; then
            # Use custom format if provided
            printf '%s' "$value"
        elif [[ "$use_commas" == "true" ]]; then
            # Add comma separators
            format_with_commas "$value"
        else
            # Return as-is
            echo "$value"
        fi
    else
        # Invalid number - return as-is
        echo "$value"
    fi
}

# Specific numeric formatters
format_number() {
    format_numeric "$1" "$2" "true"
}

format_num() {
    format_numeric "$1" "$2" "true"
}

# -----------------------------------------------------------------------------
# Float Formatting Function
# -----------------------------------------------------------------------------
# Specialized formatter for floating-point numbers with consistent decimal places.
#
# Parameters:
#   $1 - value: The float value to format
#   $2 - format: Format specification (currently unused)
#   $3 - column_index: Column index for decimal place consistency
#
# Returns:
#   Formatted float with consistent decimal places and comma separators
# -----------------------------------------------------------------------------

format_float() {
    local value="$1"
    local format="$2"
    local column_index="$3"
    
    # Handle null, empty, or zero values
    [[ -z "$value" || "$value" == "null" || "$value" == "0" ]] && {
        echo ""
        return
    }
    
    if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        # Use the maximum decimal places for this column if available
        # This ensures all floats in a column have the same decimal precision
        local max_decimals="${MAX_DECIMAL_PLACES[$column_index]:-2}"
        
        # Format with consistent decimal places
        local formatted_value
        formatted_value=$(printf "%.${max_decimals}f" "$value")
        
        # Apply thousands separators
        formatted_value=$(format_with_commas "$formatted_value")
        echo "$formatted_value"
    else
        # Invalid float - return as-is
        echo "$value"
    fi
}

# -----------------------------------------------------------------------------
# Kubernetes Unit Formatting Functions
# -----------------------------------------------------------------------------
# These functions format Kubernetes resource units (CPU and memory).
# -----------------------------------------------------------------------------

# Generic Kubernetes unit formatter
format_k_unit() {
    local value="$1"
    local format="$2"
    local unit_type="$3"
    
    # Handle null or empty values
    [[ -z "$value" || "$value" == "null" ]] && {
        echo ""
        return
    }
    
    if [[ "$unit_type" == "cpu" ]]; then
        # CPU formatting (millicores)
        [[ "$value" == "0" || "$value" == "0m" ]] && {
            echo "0m"
            return
        }
        
        if [[ "$value" =~ ^[0-9]+m$ ]]; then
            # Already in millicores format
            echo "$(format_with_commas "${value%m}")m"
        elif [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            # Convert decimal to millicores
            printf "%sm" "$(format_with_commas "$((${value%.*} * 1000))")"
        else
            echo "$value"
        fi
    else
        # Memory formatting
        [[ "$value" =~ ^0[MKG]$ || "$value" == "0Mi" || "$value" == "0Gi" || "$value" == "0Ki" ]] && {
            echo "0M"
            return
        }
        
        if [[ "$value" =~ ^[0-9]+[KMG]$ ]]; then
            # Decimal units (K, M, G)
            echo "$(format_with_commas "${value%[KMG]}")${value: -1}"
        elif [[ "$value" =~ ^[0-9]+[MGK]i$ ]]; then
            # Binary units (Ki, Mi, Gi)
            echo "$(format_with_commas "${value%?i}")${value: -2:1}"
        else
            echo "$value"
        fi
    fi
}

# Specific Kubernetes formatters
format_kcpu() {
    format_k_unit "$1" "$2" "cpu"
}

format_kmem() {
    format_k_unit "$1" "$2" "mem"
}

# -----------------------------------------------------------------------------
# Master Display Value Formatter
# -----------------------------------------------------------------------------
# This function orchestrates the formatting process by calling the appropriate
# validation and formatting functions based on the data type.
#
# Parameters:
#   $1 - value: The raw value to format
#   $2 - null_value: How to display null values ("blank", "0", "missing")
#   $3 - zero_value: How to display zero values ("blank", "0", "missing")
#   $4 - datatype: The data type (text, int, float, etc.)
#   $5 - format: Format specification
#   $6 - string_limit: Maximum string length
#   $7 - wrap_mode: Text wrapping mode
#   $8 - wrap_char: Character to wrap on
#   $9 - justification: Text alignment
#
# Returns:
#   The formatted display value
# -----------------------------------------------------------------------------

format_display_value() {
    local value="$1"
    local null_value="$2"
    local zero_value="$3"
    local datatype="$4"
    local format="$5"
    local string_limit="$6"
    local wrap_mode="$7"
    local wrap_char="$8"
    local justification="$9"
    
    # Get the appropriate validation and formatting functions for this datatype
    local validate_fn="${DATATYPE_HANDLERS[${datatype}_validate]}"
    local format_fn="${DATATYPE_HANDLERS[${datatype}_format]}"
    
    # Validate the value first
    value=$("$validate_fn" "$value")
    
    # Format the validated value
    local display_value
    display_value=$("$format_fn" "$value" "$format" "$string_limit" "$wrap_mode" "$wrap_char" "$justification")
    
    # Handle special cases for null and zero values
    if [[ "$value" == "null" ]]; then
        case "$null_value" in
            0) display_value="0" ;;
            missing) display_value="Missing" ;;
            *) display_value="" ;;
        esac
    elif [[ "$value" == "0" || "$value" == "0m" || "$value" == "0M" || "$value" == "0G" || "$value" == "0K" ]]; then
        case "$zero_value" in
            0) display_value="0" ;;
            missing) display_value="Missing" ;;
            *) display_value="" ;;
        esac
    fi
    
    echo "$display_value"
}

# =============================================================================
# tables.sh - Library for JSON to ANSI tables
# Section 04: Global Variables and Configuration Parsing
# =============================================================================
# This section handles the global variables that store table configuration,
# input file validation, and parsing of layout JSON files. It includes
# functions for parsing column configurations and sort specifications.
# =============================================================================

# -----------------------------------------------------------------------------
# Table Title and Footer Configuration
# -----------------------------------------------------------------------------
# These variables control the display of table titles and footers

# TABLE_TITLE: The title text to display above the table
declare -gx TABLE_TITLE=""

# TITLE_WIDTH: Calculated width of the title area
declare -gx TITLE_WIDTH=0

# TITLE_POSITION: Where to position the title ("left", "right", "center", "full", "none")
declare -gx TITLE_POSITION="none"

# TABLE_FOOTER: The footer text to display below the table
declare -gx TABLE_FOOTER=""

# FOOTER_WIDTH: Calculated width of the footer area
declare -gx FOOTER_WIDTH=0

# FOOTER_POSITION: Where to position the footer ("left", "right", "center", "full", "none")
declare -gx FOOTER_POSITION="none"

# -----------------------------------------------------------------------------
# Column Configuration Arrays
# -----------------------------------------------------------------------------
# These arrays store the configuration for each column in the table.
# Each array has one element per column, indexed by column number.

# Column display headers
declare -ax HEADERS=()

# JSON keys to extract data from
declare -ax KEYS=()

# Text alignment for each column ("left", "right", "center")
declare -ax JUSTIFICATIONS=()

# Data types for validation and formatting
declare -ax DATATYPES=()

# How to display null values ("blank", "0", "missing")
declare -ax NULL_VALUES=()

# How to display zero values ("blank", "0", "missing")
declare -ax ZERO_VALUES=()

# Custom format strings for each column
declare -ax FORMATS=()

# Summary types for each column ("sum", "min", "max", "avg", "count", "unique", "none")
declare -ax SUMMARIES=()

# Whether to insert breaks when values change
declare -ax BREAKS=()

# Maximum string length limits
declare -ax STRING_LIMITS=()

# Text wrapping modes ("wrap", "clip")
declare -ax WRAP_MODES=()

# Characters to wrap text on
declare -ax WRAP_CHARS=()

# Padding around cell content
declare -ax PADDINGS=()

# Column widths (calculated or specified)
declare -ax WIDTHS=()

# Sorting keys for data ordering
declare -ax SORT_KEYS=()

# Sort directions ("asc", "desc")
declare -ax SORT_DIRECTIONS=()

# Sort priorities for multi-column sorting
declare -ax SORT_PRIORITIES=()

# Whether width was explicitly specified in config
declare -ax IS_WIDTH_SPECIFIED=()

# Whether each column should be visible
declare -ax VISIBLES=()

# -----------------------------------------------------------------------------
# Theme Configuration Function
# -----------------------------------------------------------------------------
# Sets up the visual theme for the table including colors and border characters.
#
# Parameters:
#   $1 - theme_name: Name of the theme to apply ("Red", "Blue", etc.)
#
# Side Effects:
#   Populates the global THEME associative array
# -----------------------------------------------------------------------------

get_theme() {
    local theme_name="$1"
    
    # Clear any existing theme configuration
    unset THEME
    declare -g -A THEME
    
    local border_color
    local caption_color
    
    # Set colors based on theme name (case-insensitive)
    case "${theme_name,,}" in
        red)
            border_color='\033[0;31m'    # Red borders
            caption_color='\033[0;32m'   # Green captions
            ;;
        blue)
            border_color='\033[0;34m'    # Blue borders
            caption_color='\033[0;34m'   # Blue captions
            ;;
        *)
            # Default to red theme for unknown themes
            border_color='\033[0;31m'
            caption_color='\033[0;32m'
            echo -e "${border_color}Warning: Unknown theme '$theme_name', using Red\033[0m" >&2
            ;;
    esac
    
    # Configure the complete theme
    THEME=(
        # Color scheme
        [border_color]="$border_color"
        [caption_color]="$caption_color"
        [header_color]='\033[1;37m'      # Bright white headers
        [footer_color]='\033[0;36m'      # Cyan footers
        [summary_color]='\033[1;37m'     # Bright white summaries
        [text_color]='\033[0m'           # Normal text
        
        # Box drawing characters (Unicode)
        [tl_corner]='╭'                  # Top-left corner
        [tr_corner]='╮'                  # Top-right corner
        [bl_corner]='╰'                  # Bottom-left corner
        [br_corner]='╯'                  # Bottom-right corner
        [h_line]='─'                     # Horizontal line
        [v_line]='│'                     # Vertical line
        [t_junct]='┬'                    # Top junction
        [b_junct]='┴'                    # Bottom junction
        [l_junct]='├'                    # Left junction
        [r_junct]='┤'                    # Right junction
        [cross]='┼'                      # Cross junction
    )
}

# -----------------------------------------------------------------------------
# Input File Validation
# -----------------------------------------------------------------------------
# Validates that the required input files exist and are not empty.
#
# Parameters:
#   $1 - layout_file: Path to the layout JSON file
#   $2 - data_file: Path to the data JSON file
#
# Returns:
#   0 if files are valid, 1 if invalid
# -----------------------------------------------------------------------------

validate_input_files() {
    local layout_file="$1"
    local data_file="$2"
    
    # Check if files exist and are not empty
    if [[ ! -s "$layout_file" || ! -s "$data_file" ]]; then
        echo -e "${THEME[border_color]}Error: Layout or data JSON file empty/missing${THEME[text_color]}" >&2
        return 1
    fi
    
    return 0
}

# -----------------------------------------------------------------------------
# Layout File Parser
# -----------------------------------------------------------------------------
# Parses the main layout JSON file and extracts table configuration.
#
# Parameters:
#   $1 - layout_file: Path to the layout JSON file
#
# Returns:
#   0 if parsing successful, 1 if failed
#
# Side Effects:
#   Sets global variables: THEME_NAME, TABLE_TITLE, TITLE_POSITION, 
#   TABLE_FOOTER, FOOTER_POSITION, and calls column/sort parsers
# -----------------------------------------------------------------------------

parse_layout_file() {
    local layout_file="$1"
    local columns_json
    local sort_json
    
    # Extract main configuration values using jq
    THEME_NAME=$(jq -r '.theme // "Red"' "$layout_file")
    TABLE_TITLE=$(jq -r '.title // ""' "$layout_file")
    TITLE_POSITION=$(jq -r '.title_position // "none"' "$layout_file" | tr '[:upper:]' '[:lower:]')
    TABLE_FOOTER=$(jq -r '.footer // ""' "$layout_file")
    FOOTER_POSITION=$(jq -r '.footer_position // "none"' "$layout_file" | tr '[:upper:]' '[:lower:]')
    
    # Extract column and sort configurations
    columns_json=$(jq -c '.columns // []' "$layout_file")
    sort_json=$(jq -c '.sort // []' "$layout_file")
    
    # Validate position values
    case "$TITLE_POSITION" in
        left|right|center|full|none) ;;
        *)
            echo -e "${THEME[border_color]}Warning: Invalid title position '$TITLE_POSITION', using 'none'${THEME[text_color]}" >&2
            TITLE_POSITION="none"
            ;;
    esac
    
    case "$FOOTER_POSITION" in
        left|right|center|full|none) ;;
        *)
            echo -e "${THEME[border_color]}Warning: Invalid footer position '$FOOTER_POSITION', using 'none'${THEME[text_color]}" >&2
            FOOTER_POSITION="none"
            ;;
    esac
    
    # Ensure we have column definitions
    if [[ -z "$columns_json" || "$columns_json" == "[]" ]]; then
        echo -e "${THEME[border_color]}Error: No columns defined in layout JSON${THEME[text_color]}" >&2
        return 1
    fi
    
    # Parse the detailed configurations
    parse_column_config "$columns_json"
    parse_sort_config "$sort_json"
}

# -----------------------------------------------------------------------------
# Column Configuration Parser
# -----------------------------------------------------------------------------
# Parses the columns array from the layout JSON and populates column arrays.
#
# Parameters:
#   $1 - columns_json: JSON array of column configurations
#
# Side Effects:
#   Populates all column configuration arrays (HEADERS, KEYS, etc.)
# -----------------------------------------------------------------------------

parse_column_config() {
    local columns_json="$1"
    
    # Initialize all column arrays
    HEADERS=()
    KEYS=()
    JUSTIFICATIONS=()
    DATATYPES=()
    NULL_VALUES=()
    ZERO_VALUES=()
    FORMATS=()
    SUMMARIES=()
    BREAKS=()
    STRING_LIMITS=()
    WRAP_MODES=()
    WRAP_CHARS=()
    PADDINGS=()
    WIDTHS=()
    IS_WIDTH_SPECIFIED=()
    VISIBLES=()
    
    # Get the number of columns
    local column_count
    column_count=$(jq '. | length' <<<"$columns_json")
    COLUMN_COUNT=$column_count
    
    # Process each column configuration
    for ((i=0; i<column_count; i++)); do
        local col_json
        col_json=$(jq -c ".[$i]" <<<"$columns_json")
        
        # Extract column properties with defaults
        HEADERS[i]=$(jq -r '.header // ""' <<<"$col_json")
        
        # Generate key from header if not specified
        KEYS[i]=$(jq -r '.key // (.header | ascii_downcase | gsub("[^a-z0-9]"; "_"))' <<<"$col_json")
        
        JUSTIFICATIONS[i]=$(jq -r '.justification // "left"' <<<"$col_json" | tr '[:upper:]' '[:lower:]')
        DATATYPES[i]=$(jq -r '.datatype // "text"' <<<"$col_json" | tr '[:upper:]' '[:lower:]')
        NULL_VALUES[i]=$(jq -r '.null_value // "blank"' <<<"$col_json" | tr '[:upper:]' '[:lower:]')
        ZERO_VALUES[i]=$(jq -r '.zero_value // "blank"' <<<"$col_json" | tr '[:upper:]' '[:lower:]')
        FORMATS[i]=$(jq -r '.format // ""' <<<"$col_json")
        SUMMARIES[i]=$(jq -r '.summary // "none"' <<<"$col_json" | tr '[:upper:]' '[:lower:]')
        BREAKS[i]=$(jq -r '.break // false' <<<"$col_json")
        STRING_LIMITS[i]=$(jq -r '.string_limit // 0' <<<"$col_json")
        WRAP_MODES[i]=$(jq -r '.wrap_mode // "clip"' <<<"$col_json" | tr '[:upper:]' '[:lower:]')
        WRAP_CHARS[i]=$(jq -r '.wrap_char // ""' <<<"$col_json")
        PADDINGS[i]=$(jq -r '.padding // '"$DEFAULT_PADDING" <<<"$col_json")
        
        # Handle visibility with explicit check for the key
        local visible_raw
        local visible_key_check
        visible_raw=$(jq -r '.visible // true' <<<"$col_json")
        visible_key_check=$(jq -r 'has("visible")' <<<"$col_json")
        
        if [[ "$visible_key_check" == "true" ]]; then
            VISIBLES[i]=$(jq -r '.visible' <<<"$col_json")
        else
            VISIBLES[i]="$visible_raw"
        fi
        
        # Handle width specification
        local specified_width
        specified_width=$(jq -r '.width // 0' <<<"$col_json")
        
        if [[ $specified_width -gt 0 ]]; then
            WIDTHS[i]=$specified_width
            IS_WIDTH_SPECIFIED[i]="true"
        else
            # Calculate minimum width based on header length and padding
            WIDTHS[i]=$((${#HEADERS[i]} + (2 * PADDINGS[i])))
            IS_WIDTH_SPECIFIED[i]="false"
        fi
        
        # Validate the column configuration
        validate_column_config "$i" "${HEADERS[$i]}" "${JUSTIFICATIONS[$i]}" "${DATATYPES[$i]}" "${SUMMARIES[$i]}"
    done
}

# -----------------------------------------------------------------------------
# Column Configuration Validator
# -----------------------------------------------------------------------------
# Validates individual column settings and corrects invalid values.
#
# Parameters:
#   $1 - i: Column index
#   $2 - header: Column header text
#   $3 - justification: Text alignment
#   $4 - datatype: Data type
#   $5 - summary: Summary type
#
# Side Effects:
#   May modify global arrays to correct invalid values
# -----------------------------------------------------------------------------

validate_column_config() {
    local i="$1"
    local header="$2"
    local justification="$3"
    local datatype="$4"
    local summary="$5"
    
    # Header is required
    if [[ -z "$header" ]]; then
        echo -e "${THEME[border_color]}Error: Column $i has no header${THEME[text_color]}" >&2
        return 1
    fi
    
    # Validate justification
    if [[ "$justification" != "left" && "$justification" != "right" && "$justification" != "center" ]]; then
        echo -e "${THEME[border_color]}Warning: Invalid justification '$justification' for column $header, using 'left'${THEME[text_color]}" >&2
        JUSTIFICATIONS[i]="left"
    fi
    
    # Validate datatype
    if [[ -z "${DATATYPE_HANDLERS[${datatype}_validate]}" ]]; then
        echo -e "${THEME[border_color]}Warning: Invalid datatype '$datatype' for column $header, using 'text'${THEME[text_color]}" >&2
        DATATYPES[i]="text"
    fi
    
    # Validate summary type against datatype capabilities
    local valid_summaries="${DATATYPE_HANDLERS[${DATATYPES[$i]}_summary_types]}"
    if [[ "$summary" != "none" && ! " $valid_summaries " =~ $summary ]]; then
        echo -e "${THEME[border_color]}Warning: Summary '$summary' not supported for datatype '${DATATYPES[$i]}' in column $header, using 'none'${THEME[text_color]}" >&2
        SUMMARIES[i]="none"
    fi
}

# -----------------------------------------------------------------------------
# Sort Configuration Parser
# -----------------------------------------------------------------------------
# Parses the sort array from the layout JSON and populates sort arrays.
#
# Parameters:
#   $1 - sort_json: JSON array of sort configurations
#
# Side Effects:
#   Populates SORT_KEYS, SORT_DIRECTIONS, and SORT_PRIORITIES arrays
# -----------------------------------------------------------------------------

parse_sort_config() {
    local sort_json="$1"
    
    # Initialize sort arrays
    SORT_KEYS=()
    SORT_DIRECTIONS=()
    SORT_PRIORITIES=()
    
    # Get the number of sort specifications
    local sort_count
    sort_count=$(jq '. | length' <<<"$sort_json")
    
    # Process each sort specification
    for ((i=0; i<sort_count; i++)); do
        local sort_item
        sort_item=$(jq -c ".[$i]" <<<"$sort_json")
        
        # Extract sort properties
        SORT_KEYS[i]=$(jq -r '.key // ""' <<<"$sort_item")
        SORT_DIRECTIONS[i]=$(jq -r '.direction // "asc"' <<<"$sort_item" | tr '[:upper:]' '[:lower:]')
        SORT_PRIORITIES[i]=$(jq -r '.priority // 0' <<<"$sort_item")
        
        # Validate sort key
        if [[ -z "${SORT_KEYS[$i]}" ]]; then
            echo -e "${THEME[border_color]}Warning: Sort item $i has no key, ignoring${THEME[text_color]}" >&2
            continue
        fi
        
        # Validate sort direction
        if [[ "${SORT_DIRECTIONS[$i]}" != "asc" && "${SORT_DIRECTIONS[$i]}" != "desc" ]]; then
            echo -e "${THEME[border_color]}Warning: Invalid sort direction '${SORT_DIRECTIONS[$i]}' for key ${SORT_KEYS[$i]}, using 'asc'${THEME[text_color]}" >&2
            SORT_DIRECTIONS[i]="asc"
        fi
    done
}
# =============================================================================
# tables.sh - Library for JSON to ANSI tables
# Section 05: Data Processing and Sorting Functions
# =============================================================================
# This section handles the loading, processing, and sorting of data from JSON
# files. It includes summary initialization, data preparation from JSON,
# and sorting functionality.
# =============================================================================

# -----------------------------------------------------------------------------
# Data Storage Arrays
# -----------------------------------------------------------------------------
# These arrays store the processed data and summary calculations

# ROW_JSONS: Array of JSON objects representing each row (for metadata)
declare -a ROW_JSONS=()

# DATA_ROWS: Array of serialized associative arrays containing row data
declare -a DATA_ROWS=()

# -----------------------------------------------------------------------------
# Summary Calculation Storage
# -----------------------------------------------------------------------------
# These associative arrays store running totals and calculations for summaries.
# Each is indexed by column number.

# Sum totals for numeric columns
declare -A SUM_SUMMARIES=()

# Count of non-null values per column
declare -A COUNT_SUMMARIES=()

# Minimum values per column
declare -A MIN_SUMMARIES=()

# Maximum values per column
declare -A MAX_SUMMARIES=()

# Unique values tracking (space-separated strings)
declare -A UNIQUE_VALUES=()

# Running totals for average calculations
declare -A AVG_SUMMARIES=()

# Count of values used in average calculations
declare -A AVG_COUNTS=()

# Maximum decimal places found in float columns
declare -A MAX_DECIMAL_PLACES=()

# -----------------------------------------------------------------------------
# Summary Initialization Function
# -----------------------------------------------------------------------------
# Initializes all summary tracking arrays with default values for each column.
# This must be called before processing any data.
#
# Side Effects:
#   Resets all summary arrays and populates them with default values
# -----------------------------------------------------------------------------

initialize_summaries() {
    # Clear existing summary data
    SUM_SUMMARIES=()
    COUNT_SUMMARIES=()
    MIN_SUMMARIES=()
    MAX_SUMMARIES=()
    UNIQUE_VALUES=()
    AVG_SUMMARIES=()
    AVG_COUNTS=()
    MAX_DECIMAL_PLACES=()
    
    # Initialize default values for each column
    for ((i=0; i<COLUMN_COUNT; i++)); do
        SUM_SUMMARIES[$i]=0
        COUNT_SUMMARIES[$i]=0
        MIN_SUMMARIES[$i]=""          # Empty means no minimum found yet
        MAX_SUMMARIES[$i]=""          # Empty means no maximum found yet
        UNIQUE_VALUES[$i]=""          # Empty means no unique values yet
        AVG_SUMMARIES[$i]=0
        AVG_COUNTS[$i]=0
        MAX_DECIMAL_PLACES[$i]=0
    done
}

# -----------------------------------------------------------------------------
# Data Preparation Function
# -----------------------------------------------------------------------------
# Loads and processes data from a JSON file, extracting values for each
# configured column and storing them in a format suitable for rendering.
#
# Parameters:
#   $1 - data_file: Path to the JSON data file
#
# Side Effects:
#   Populates the DATA_ROWS array with processed row data
# -----------------------------------------------------------------------------

prepare_data() {
    local data_file="$1"
    
    # Clear existing data
    DATA_ROWS=()
    
    # Load and validate JSON data
    local data_json
    data_json=$(jq -c '. // []' "$data_file")
    
    # Get the number of rows in the data
    local row_count
    row_count=$(jq '. | length' <<<"$data_json")
    
    # If no data, return early
    [[ $row_count -eq 0 ]] && return
    
    # Build a jq expression to extract all required fields efficiently
    # This creates a single jq command that extracts all column values
    # and joins them with tabs for easy parsing
    local jq_expr=".[] | ["
    for key in "${KEYS[@]}"; do
        jq_expr+=".${key} // null,"
    done
    jq_expr="${jq_expr%,}] | join(\"\t\")"
    
    # Extract all data in one jq call for efficiency
    local all_data
    all_data=$(jq -r "$jq_expr" "$data_file")
    
    # Split the data into individual rows
    IFS=$'\n' read -d '' -r -a rows <<< "$all_data"
    
    # Process each row of data
    for ((i=0; i<row_count; i++)); do
        # Split the tab-separated values
        IFS=$'\t' read -r -a values <<< "${rows[$i]}"
        
        # Create an associative array for this row
        declare -A row_data
        
        # Populate the associative array with column values
        for ((j=0; j<${#KEYS[@]}; j++)); do
            local key="${KEYS[$j]}"
            local value="${values[$j]}"
            
            # Handle null values consistently
            if [[ "$value" == "null" ]]; then
                value="null"
            else
                # Use the value or default to null if empty
                value="${value:-null}"
            fi
            
            row_data["$key"]="$value"
        done
        
        # Serialize the associative array for storage
        # This allows us to recreate the array later using eval
        local row_data_str
        row_data_str=$(declare -p row_data)
        DATA_ROWS[i]="$row_data_str"
    done
}

# -----------------------------------------------------------------------------
# Data Sorting Function
# -----------------------------------------------------------------------------
# Sorts the data rows according to the configured sort specifications.
# Currently implements single-key sorting (primary sort key only).
#
# Side Effects:
#   Reorders the DATA_ROWS array according to sort configuration
# -----------------------------------------------------------------------------

sort_data() {
    # Skip sorting if no sort keys are configured
    [[ ${#SORT_KEYS[@]} -eq 0 ]] && return
    
    # Create an array of indices for sorting
    local indices=()
    for ((i=0; i<${#DATA_ROWS[@]}; i++)); do
        indices+=("$i")
    done
    
    # Helper function to extract sort values from a row
    # Parameters:
    #   $1 - idx: Index of the row in DATA_ROWS
    #   $2 - key: The key to extract from the row data
    # Returns:
    #   The value for the specified key, or empty string if not found
    get_sort_value() {
        local idx="$1"
        local key="$2"
        
        # Recreate the associative array from the serialized data
        declare -A row_data
        if ! eval "${DATA_ROWS[$idx]}"; then
            echo ""
            return
        fi
        
        # Return the value for the requested key
        if [[ -v "row_data[$key]" ]]; then
            echo "${row_data[$key]}"
        else
            echo ""
        fi
    }
    
    # Get the primary sort configuration
    # Note: This implementation only handles single-key sorting
    # Multi-key sorting would require more complex logic
    local primary_key="${SORT_KEYS[0]}"
    local primary_dir="${SORT_DIRECTIONS[0]}"
    
    # Perform the sort using bash's built-in sort command
    # We create a list of "value<tab>index" pairs, sort them, then extract indices
    local sorted_indices=()
    IFS=$'\n' read -d '' -r -a sorted_indices < <(
        for idx in "${indices[@]}"; do
            value=$(get_sort_value "$idx" "$primary_key")
            printf "%s\t%s\n" "$value" "$idx"
        done | sort -k1,1"${primary_dir:0:1}" | cut -f2
    )
    
    # Reorder DATA_ROWS according to the sorted indices
    local temp_rows=("${DATA_ROWS[@]}")
    DATA_ROWS=()
    
    for idx in "${sorted_indices[@]}"; do
        DATA_ROWS+=("${temp_rows[$idx]}")
    done
}

# =============================================================================
# tables.sh - Library for JSON to ANSI tables
# Section 06: Row Processing and Summary Calculations
# =============================================================================
# This section handles the processing of data rows, including formatting values
# for display, calculating column widths, updating summary statistics, and
# formatting summary values for display.
# =============================================================================

# -----------------------------------------------------------------------------
# Main Row Processing Function
# -----------------------------------------------------------------------------
# Processes all data rows to format values, calculate column widths, and
# update summary statistics. This is one of the most complex functions as it
# handles multiple concerns simultaneously for efficiency.
#
# Side Effects:
#   - Updates WIDTHS array with calculated column widths
#   - Updates MAX_LINES with the maximum row height
#   - Updates all summary arrays with calculated statistics
#   - Populates ROW_JSONS array with row metadata
# -----------------------------------------------------------------------------

process_data_rows() {
    local row_count
    
    # Initialize tracking variables
    MAX_LINES=1  # Track the maximum number of lines in any row
    row_count=${#DATA_ROWS[@]}
    
    # If no data, return early
    [[ $row_count -eq 0 ]] && return
    
    # Initialize row metadata array
    ROW_JSONS=()
    
    # Process each row of data
    for ((i=0; i<row_count; i++)); do
        local row_json
        local line_count=1  # Track lines in this specific row
        
        # Create basic row metadata
        row_json="{\"row\":$i}"
        ROW_JSONS+=("$row_json")
        
        # Recreate the associative array from serialized data
        declare -A row_data
        if ! eval "${DATA_ROWS[$i]}"; then
            continue  # Skip malformed rows
        fi
        
        # Process each column in this row
        for ((j=0; j<COLUMN_COUNT; j++)); do
            local key="${KEYS[$j]}"
            local datatype="${DATATYPES[$j]}"
            local format="${FORMATS[$j]}"
            local string_limit="${STRING_LIMITS[$j]}"
            local wrap_mode="${WRAP_MODES[$j]}"
            local wrap_char="${WRAP_CHARS[$j]}"
            
            # Get validation and formatting functions for this datatype
            local validate_fn="${DATATYPE_HANDLERS[${datatype}_validate]}"
            local format_fn="${DATATYPE_HANDLERS[${datatype}_format]}"
            
            # Extract and validate the value
            local value="null"
            if [[ -v "row_data[$key]" ]]; then
                value="${row_data[$key]}"
            fi
            
            value=$("$validate_fn" "$value")
            
            # Format the value for display
            local display_value
            if [[ "$datatype" == "float" ]]; then
                # Float formatting requires special handling for decimal places
                display_value=$("$format_fn" "$value" "$format" "$j")
            else
                # Standard formatting for other datatypes
                display_value=$("$format_fn" "$value" "$format" "$string_limit" "$wrap_mode" "$wrap_char")
            fi
            
            # Handle null and zero value display preferences
            if [[ "$value" == "null" ]]; then
                case "${NULL_VALUES[$j]}" in
                    0) display_value="0" ;;
                    missing) display_value="Missing" ;;
                    *) display_value="" ;;
                esac
            elif [[ "$value" == "0" || "$value" == "0m" || "$value" == "0M" || "$value" == "0G" || "$value" == "0K" ]]; then
                case "${ZERO_VALUES[$j]}" in
                    0) display_value="0" ;;
                    missing) display_value="Missing" ;;
                    *) display_value="" ;;
                esac
            fi
            
            # Calculate column width requirements (only for auto-sized visible columns)
            if [[ "${IS_WIDTH_SPECIFIED[j]}" != "true" && "${VISIBLES[j]}" == "true" ]]; then
                if [[ -n "$wrap_char" && "$wrap_mode" == "wrap" && -n "$display_value" && "$value" != "null" ]]; then
                    # Handle character-based wrapping
                    local max_len=0
                    local IFS="$wrap_char"
                    read -ra parts <<<"$display_value"
                    
                    # Find the longest part after wrapping
                    for part in "${parts[@]}"; do
                        local len
                        len=$(get_display_length "$part")
                        [[ $len -gt $max_len ]] && max_len=$len
                    done
                    
                    # Update column width if this is wider
                    local padded_width=$((max_len + (2 * PADDINGS[j])))
                    [[ $padded_width -gt ${WIDTHS[j]} ]] && WIDTHS[j]=$padded_width
                    
                    # Update row line count if this cell has more lines
                    [[ ${#parts[@]} -gt $line_count ]] && line_count=${#parts[@]}
                else
                    # Handle normal (non-wrapped) content
                    local len
                    len=$(get_display_length "$display_value")
                    local padded_width=$((len + (2 * PADDINGS[j])))
                    [[ $padded_width -gt ${WIDTHS[j]} ]] && WIDTHS[j]=$padded_width
                fi
            fi
            
            # Update summary statistics for this value
            update_summaries "$j" "$value" "${DATATYPES[$j]}" "${SUMMARIES[$j]}"
        done
        
        # Update global maximum line count
        [[ $line_count -gt $MAX_LINES ]] && MAX_LINES=$line_count
    done
    
    # After processing all rows, check if summary values affect column widths
    for ((j=0; j<COLUMN_COUNT; j++)); do
        if [[ "${SUMMARIES[$j]}" != "none" ]]; then
            local summary_value
            summary_value=$(format_summary_value "$j" "${SUMMARIES[$j]}" "${DATATYPES[$j]}" "${FORMATS[$j]}")
            
            # Update column width if summary is wider than current width
            if [[ -n "$summary_value" && "${IS_WIDTH_SPECIFIED[j]}" != "true" && "${VISIBLES[j]}" == "true" ]]; then
                local summary_len
                summary_len=$(get_display_length "$summary_value")
                local summary_padded_width=$((summary_len + (2 * PADDINGS[j])))
                [[ $summary_padded_width -gt ${WIDTHS[j]} ]] && WIDTHS[j]=$summary_padded_width
            fi
        fi
    done
}

# -----------------------------------------------------------------------------
# Summary Statistics Update Function
# -----------------------------------------------------------------------------
# Updates running summary statistics for a single value. This function handles
# different summary types (sum, min, max, avg, count, unique) and different
# data types with their specific calculation requirements.
#
# Parameters:
#   $1 - j: Column index
#   $2 - value: The value to include in summary calculations
#   $3 - datatype: The data type of the value
#   $4 - summary_type: The type of summary to calculate
#
# Side Effects:
#   Updates the appropriate summary arrays (SUM_SUMMARIES, MIN_SUMMARIES, etc.)
# -----------------------------------------------------------------------------

update_summaries() {
    local j="$1"
    local value="$2"
    local datatype="$3"
    local summary_type="$4"
    
    # Track maximum decimal places for float data type
    # This ensures consistent formatting across all float values in a column
    if [[ "$datatype" == "float" && "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        local decimal_part="${value#*.}"
        local decimal_places=0
        
        # Count decimal places if there's a decimal part
        if [[ -n "$decimal_part" && "$decimal_part" != "$value" ]]; then
            decimal_places=${#decimal_part}
        fi
        
        # Update maximum if this value has more decimal places
        if [[ $decimal_places -gt ${MAX_DECIMAL_PLACES[$j]:-0} ]]; then
            MAX_DECIMAL_PLACES[$j]=$decimal_places
        fi
    fi
    
    # Process the summary calculation based on type
    case "$summary_type" in
        sum)
            # Sum calculation - handles different data types differently
            if [[ "$datatype" == "kcpu" && "$value" =~ ^[0-9]+m$ ]]; then
                # Kubernetes CPU in millicores - sum the numeric part
                SUM_SUMMARIES[$j]=$(( ${SUM_SUMMARIES[$j]:-0} + ${value%m} ))
                
            elif [[ "$datatype" == "kmem" ]]; then
                # Kubernetes memory - normalize to a common unit (MB) for summing
                if [[ "$value" =~ ^[0-9]+M$ ]]; then
                    SUM_SUMMARIES[$j]=$(( ${SUM_SUMMARIES[$j]:-0} + ${value%M} ))
                elif [[ "$value" =~ ^[0-9]+G$ ]]; then
                    SUM_SUMMARIES[$j]=$(( ${SUM_SUMMARIES[$j]:-0} + ${value%G} * 1000 ))
                elif [[ "$value" =~ ^[0-9]+K$ ]]; then
                    SUM_SUMMARIES[$j]=$(( ${SUM_SUMMARIES[$j]:-0} + ${value%K} / 1000 ))
                elif [[ "$value" =~ ^[0-9]+Mi$ ]]; then
                    SUM_SUMMARIES[$j]=$(( ${SUM_SUMMARIES[$j]:-0} + ${value%Mi} ))
                elif [[ "$value" =~ ^[0-9]+Gi$ ]]; then
                    SUM_SUMMARIES[$j]=$(( ${SUM_SUMMARIES[$j]:-0} + ${value%Gi} * 1000 ))
                fi
                
            elif [[ "$datatype" == "int" || "$datatype" == "num" ]]; then
                # Integer/numeric types - sum directly
                if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    local int_value=${value%.*}
                    [[ "$int_value" == "$value" ]] && int_value=$value
                    SUM_SUMMARIES[$j]=$((${SUM_SUMMARIES[$j]:-0} + int_value))
                fi
                
            elif [[ "$datatype" == "float" ]]; then
                # Float types - use bc for precision
                if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    SUM_SUMMARIES[$j]=$(echo "${SUM_SUMMARIES[$j]:-0} + $value" | bc)
                fi
            fi
            ;;
            
        min)
            # Minimum calculation - find the smallest value
            if [[ "$datatype" == "kcpu" && "$value" =~ ^[0-9]+m$ ]]; then
                local num_val="${value%m}"
                if [[ -z "${MIN_SUMMARIES[$j]}" ]] || (( num_val < ${MIN_SUMMARIES[$j]:-999999} )); then
                    MIN_SUMMARIES[$j]="$num_val"
                fi
                
            elif [[ "$datatype" == "kmem" && "$value" =~ ^[0-9]+[KMG]$ ]]; then
                # Normalize memory units for comparison
                local num_val="${value%[KMG]}"
                local unit="${value: -1}"
                if [[ "$unit" == "G" ]]; then
                    num_val=$((num_val * 1000))
                elif [[ "$unit" == "K" ]]; then
                    num_val=$((num_val / 1000))
                fi
                
                if [[ -z "${MIN_SUMMARIES[$j]}" ]] || (( num_val < ${MIN_SUMMARIES[$j]:-999999} )); then
                    MIN_SUMMARIES[$j]="$num_val"
                fi
                
            elif [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                # Numeric comparison
                if [[ -z "${MIN_SUMMARIES[$j]}" ]] || (( $(printf "%.0f" "$value") < $(printf "%.0f" "${MIN_SUMMARIES[$j]:-999999}") )); then
                    MIN_SUMMARIES[$j]="$value"
                fi
            fi
            ;;
            
        max)
            # Maximum calculation - find the largest value
            if [[ "$datatype" == "kcpu" && "$value" =~ ^[0-9]+m$ ]]; then
                local num_val="${value%m}"
                if [[ -z "${MAX_SUMMARIES[$j]}" ]] || (( num_val > ${MAX_SUMMARIES[$j]:-0} )); then
                    MAX_SUMMARIES[$j]="$num_val"
                fi
                
            elif [[ "$datatype" == "kmem" && "$value" =~ ^[0-9]+[KMG]$ ]]; then
                # Normalize memory units for comparison
                local num_val="${value%[KMG]}"
                local unit="${value: -1}"
                if [[ "$unit" == "G" ]]; then
                    num_val=$((num_val * 1000))
                elif [[ "$unit" == "K" ]]; then
                    num_val=$((num_val / 1000))
                fi
                
                if [[ -z "${MAX_SUMMARIES[$j]}" ]] || (( num_val > ${MAX_SUMMARIES[$j]:-0} )); then
                    MAX_SUMMARIES[$j]="$num_val"
                fi
                
            elif [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                # Numeric comparison
                if [[ -z "${MAX_SUMMARIES[$j]}" ]] || (( $(printf "%.0f" "$value") > $(printf "%.0f" "${MAX_SUMMARIES[$j]:-0}") )); then
                    MAX_SUMMARIES[$j]="$value"
                fi
            fi
            ;;
            
        count)
            # Count non-null values
            if [[ -n "$value" && "$value" != "null" ]]; then
                COUNT_SUMMARIES[$j]=$(( ${COUNT_SUMMARIES[$j]:-0} + 1 ))
            fi
            ;;
            
        unique)
            # Track unique values (space-separated list)
            if [[ -n "$value" && "$value" != "null" ]]; then
                if [[ -z "${UNIQUE_VALUES[$j]}" ]]; then
                    UNIQUE_VALUES[$j]="$value"
                else
                    UNIQUE_VALUES[$j]+=" $value"
                fi
            fi
            ;;
            
        avg)
            # Average calculation - accumulate sum and count
            if [[ "$datatype" == "int" || "$datatype" == "float" || "$datatype" == "num" ]]; then
                if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    if [[ "$datatype" == "float" ]]; then
                        # Use bc for floating-point precision
                        AVG_SUMMARIES[$j]=$(echo "${AVG_SUMMARIES[$j]:-0} + $value" | bc)
                    else
                        # Integer arithmetic for int/num types
                        local int_value=${value%.*}
                        [[ "$int_value" == "$value" ]] && int_value=$value
                        AVG_SUMMARIES[$j]=$((${AVG_SUMMARIES[$j]:-0} + int_value))
                    fi
                    AVG_COUNTS[$j]=$(( ${AVG_COUNTS[$j]:-0} + 1 ))
                fi
            fi
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Summary Value Formatting Function
# -----------------------------------------------------------------------------
# Formats calculated summary values for display, applying appropriate
# formatting based on the data type and summary type.
#
# Parameters:
#   $1 - j: Column index
#   $2 - summary_type: Type of summary (sum, min, max, avg, count, unique)
#   $3 - datatype: Data type of the column
#   $4 - format: Format specification for the column
#
# Returns:
#   Formatted summary value ready for display
# -----------------------------------------------------------------------------

format_summary_value() {
    local j="$1"
    local summary_type="$2"
    local datatype="$3"
    local format="$4"
    local summary_value=""
    
    case "$summary_type" in
        sum)
            # Format sum values according to data type
            if [[ -n "${SUM_SUMMARIES[$j]}" && "${SUM_SUMMARIES[$j]}" != "0" ]]; then
                if [[ "$datatype" == "kcpu" ]]; then
                    summary_value="$(format_with_commas "${SUM_SUMMARIES[$j]}")m"
                elif [[ "$datatype" == "kmem" ]]; then
                    summary_value="$(format_with_commas "${SUM_SUMMARIES[$j]}")M"
                elif [[ "$datatype" == "num" ]]; then
                    summary_value=$(format_num "${SUM_SUMMARIES[$j]}" "$format")
                elif [[ "$datatype" == "int" ]]; then
                    summary_value=$(format_with_commas "${SUM_SUMMARIES[$j]}")
                elif [[ "$datatype" == "float" ]]; then
                    local decimals=${MAX_DECIMAL_PLACES[$j]:-2}
                    local formatted_sum=$(printf "%.${decimals}f" "${SUM_SUMMARIES[$j]}")
                    summary_value=$(format_with_commas "$formatted_sum")
                fi
            fi
            ;;
            
        min)
            # Format minimum values
            summary_value="${MIN_SUMMARIES[$j]:-}"
            if [[ "$datatype" == "kcpu" && -n "$summary_value" ]]; then
                summary_value="$(format_with_commas "$summary_value")m"
            elif [[ "$datatype" == "kmem" && -n "$summary_value" ]]; then
                summary_value="$(format_with_commas "$summary_value")M"
            elif [[ "$datatype" == "float" && -n "$summary_value" && -n "${MAX_DECIMAL_PLACES[$j]}" ]]; then
                local decimals=${MAX_DECIMAL_PLACES[$j]:-2}
                local formatted_min=$(printf "%.${decimals}f" "$summary_value")
                summary_value=$(format_with_commas "$formatted_min")
            elif [[ "$datatype" == "int" && -n "$summary_value" ]]; then
                summary_value=$(format_with_commas "$summary_value")
            fi
            ;;
            
        max)
            # Format maximum values
            summary_value="${MAX_SUMMARIES[$j]:-}"
            if [[ "$datatype" == "kcpu" && -n "$summary_value" ]]; then
                summary_value="$(format_with_commas "$summary_value")m"
            elif [[ "$datatype" == "kmem" && -n "$summary_value" ]]; then
                summary_value="$(format_with_commas "$summary_value")M"
            elif [[ "$datatype" == "float" && -n "$summary_value" && -n "${MAX_DECIMAL_PLACES[$j]}" ]]; then
                local decimals=${MAX_DECIMAL_PLACES[$j]:-2}
                local formatted_max=$(printf "%.${decimals}f" "$summary_value")
                summary_value=$(format_with_commas "$formatted_max")
            elif [[ "$datatype" == "int" && -n "$summary_value" ]]; then
                summary_value=$(format_with_commas "$summary_value")
            fi
            ;;
            
        count)
            # Count is always an integer
            summary_value="${COUNT_SUMMARIES[$j]:-0}"
            ;;
            
        unique)
            # Count unique values
            if [[ -n "${UNIQUE_VALUES[$j]}" ]]; then
                summary_value=$(echo "${UNIQUE_VALUES[$j]}" | tr ' ' '\n' | sort -u | wc -l)
            else
                summary_value="0"
            fi
            ;;
            
        avg)
            # Calculate and format average values
            if [[ -n "${AVG_SUMMARIES[$j]}" && "${AVG_COUNTS[$j]}" -gt 0 ]]; then
                if [[ "$datatype" == "float" ]]; then
                    local decimals=${MAX_DECIMAL_PLACES[$j]:-2}
                    local avg_result=$(awk "BEGIN {printf \"%.${decimals}f\", (${AVG_SUMMARIES[$j]}) / (${AVG_COUNTS[$j]})}")
                    summary_value=$(format_with_commas "$avg_result")
                elif [[ "$datatype" == "int" ]]; then
                    local avg_result=$((${AVG_SUMMARIES[$j]} / ${AVG_COUNTS[$j]}))
                    summary_value=$(format_with_commas "$avg_result")
                elif [[ "$datatype" == "num" ]]; then
                    local avg_result=$((${AVG_SUMMARIES[$j]} / ${AVG_COUNTS[$j]}))
                    summary_value=$(format_num "$avg_result" "$format")
                else
                    summary_value="$((${AVG_SUMMARIES[$j]} / ${AVG_COUNTS[$j]}))"
                fi
            else
                summary_value="0"
            fi
            ;;
    esac
    
    echo "$summary_value"
}

# =============================================================================
# tables.sh - Library for JSON to ANSI tables
# Section 07: Width Calculations and Layout Functions
# =============================================================================
# This section handles the calculation of widths for various table elements
# including titles, footers, and the overall table dimensions. These functions
# are crucial for proper table layout and alignment.
# =============================================================================

# -----------------------------------------------------------------------------
# Generic Element Width Calculator
# -----------------------------------------------------------------------------
# Calculates the display width for table elements (titles, footers) based on
# their content, position, and the overall table width. This is a helper
# function used by the specific title and footer width calculators.
#
# Parameters:
#   $1 - text: The text content of the element
#   $2 - total_table_width: The total width of the table
#   $3 - position: Position setting ("left", "right", "center", "full", "none")
#   $4 - width_var: Name of the variable to store the calculated width
#
# Side Effects:
#   Sets the global variable specified by width_var to the calculated width
# -----------------------------------------------------------------------------

calculate_element_width() {
    local text="$1"
    local total_table_width="$2"
    local position="$3"
    local width_var="$4"
    
    # If there's no text, width is zero
    if [[ -n "$text" ]]; then
        local evaluated_text
        
        # Safely evaluate the text (it might contain variables or commands)
        # The 2>/dev/null suppresses any errors from evaluation
        evaluated_text=$(eval "echo \"$text\"" 2>/dev/null)
        
        # Replace color placeholders with actual ANSI codes
        evaluated_text=$(replace_color_placeholders "$evaluated_text")
        
        # Process any escape sequences in the text
        evaluated_text=$(printf '%b' "$evaluated_text")
        
        # Calculate the actual display length (accounting for ANSI codes, Unicode, etc.)
        local text_length
        text_length=$(get_display_length "$evaluated_text")
        
        # Determine the appropriate width based on position
        if [[ "$position" == "none" ]]; then
            # For "none" position, width is just text length plus padding
            declare -g "$width_var"=$((text_length + (2 * DEFAULT_PADDING)))
            
        elif [[ "$position" == "full" ]]; then
            # For "full" position, use the entire table width
            declare -g "$width_var"=$total_table_width
            
        else
            # For other positions (left, right, center), calculate based on text
            declare -g "$width_var"=$((text_length + (2 * DEFAULT_PADDING)))
            
            # Ensure the width doesn't exceed the table width
            [[ ${!width_var} -gt $total_table_width ]] && declare -g "$width_var"=$total_table_width
        fi
    else
        # No text means zero width
        declare -g "$width_var"=0
    fi
}

# -----------------------------------------------------------------------------
# Title Width Calculator
# -----------------------------------------------------------------------------
# Calculates the width required for the table title based on its content
# and position setting.
#
# Parameters:
#   $1 - title_text: The title text (may contain variables/placeholders)
#   $2 - total_table_width: The total width of the table
#
# Side Effects:
#   Sets the global TITLE_WIDTH variable
# -----------------------------------------------------------------------------

calculate_title_width() {
    calculate_element_width "$1" "$2" "$TITLE_POSITION" "TITLE_WIDTH"
}

# -----------------------------------------------------------------------------
# Footer Width Calculator
# -----------------------------------------------------------------------------
# Calculates the width required for the table footer based on its content
# and position setting.
#
# Parameters:
#   $1 - footer_text: The footer text (may contain variables/placeholders)
#   $2 - total_table_width: The total width of the table
#
# Side Effects:
#   Sets the global FOOTER_WIDTH variable
# -----------------------------------------------------------------------------

calculate_footer_width() {
    calculate_element_width "$1" "$2" "$FOOTER_POSITION" "FOOTER_WIDTH"
}

# -----------------------------------------------------------------------------
# Total Table Width Calculator
# -----------------------------------------------------------------------------
# Calculates the total width of the table by summing the widths of all
# visible columns plus the space needed for column separators.
#
# The calculation includes:
# - Width of each visible column (including padding)
# - Vertical separators between columns (1 character each)
#
# Returns:
#   The total table width in characters
# -----------------------------------------------------------------------------

calculate_table_width() {
    local total_table_width=0
    local visible_count=0
    
    # Sum the widths of all visible columns
    for ((i=0; i<COLUMN_COUNT; i++)); do
        if [[ "${VISIBLES[i]}" == "true" ]]; then
            ((total_table_width += WIDTHS[i]))
            ((visible_count++))
        fi
    done
    
    # Add space for column separators
    # There's one separator between each pair of adjacent visible columns
    # So for N visible columns, we need N-1 separators
    [[ $visible_count -gt 1 ]] && ((total_table_width += visible_count - 1))
    
    echo "$total_table_width"
}

# =============================================================================
# tables.sh - Library for JSON to ANSI tables
# Section 08: Text Clipping and Cell Rendering Functions
# =============================================================================
# This section handles the rendering of individual table cells and the clipping
# of text that exceeds available space. It includes functions for text
# truncation with different justification modes and the core cell rendering
# logic that handles padding, alignment, and color formatting.
# =============================================================================

# -----------------------------------------------------------------------------
# Text Clipping Function
# -----------------------------------------------------------------------------
# Clips text to fit within a specified width, respecting different justification
# modes. This function is essential for ensuring text fits within column
# constraints while maintaining proper alignment.
#
# Parameters:
#   $1 - text: The text to clip
#   $2 - width: Maximum width in display characters
#   $3 - justification: How to clip ("left", "right", "center")
#
# Returns:
#   The clipped text that fits within the specified width
# -----------------------------------------------------------------------------

clip_text() {
    local text="$1"
    local width="$2"
    local justification="$3"
    
    # Calculate the actual display length of the text
    local display_length
    display_length=$(get_display_length "$text")
    
    # If text already fits, return it unchanged
    if [[ $display_length -le $width ]]; then
        echo "$text"
        return
    fi
    
    # Special handling for text containing ANSI escape sequences
    # These are complex to clip properly, so we return them as-is
    # and let the terminal handle any overflow
    if [[ "$text" =~ $'\033\[' ]]; then
        echo "$text"
        return
    fi
    
    # Clip the text based on justification mode
    case "$justification" in
        right)
            # Right justification: keep the rightmost characters
            echo "${text: -${width}}"
            ;;
        center)
            # Center justification: remove equal amounts from both sides
            local excess=$(( display_length - width ))
            local left_clip=$(( excess / 2 ))
            echo "${text:${left_clip}:${width}}"
            ;;
        *)
            # Left justification (default): keep the leftmost characters
            echo "${text:0:${width}}"
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Cell Rendering Function
# -----------------------------------------------------------------------------
# Renders a single table cell with proper padding, alignment, and color
# formatting. This is one of the core rendering functions that handles
# the visual presentation of cell content.
#
# Parameters:
#   $1 - content: The text content to display in the cell
#   $2 - width: Total width of the cell (including padding)
#   $3 - padding: Amount of padding on each side
#   $4 - justification: Text alignment ("left", "right", "center")
#   $5 - color: ANSI color code for the content
#
# Output:
#   Formatted cell content with padding, alignment, and border
# -----------------------------------------------------------------------------

render_cell() {
    local content="$1"
    local width="$2"
    local padding="$3"
    local justification="$4"
    local color="$5"
    
    # Calculate the available width for content (excluding padding)
    local content_width=$((width - (2 * padding)))
    
    # Render the cell based on justification mode
    case "$justification" in
        right)
            # Right-aligned content
            # Format: [padding][right-aligned content][padding][border]
            printf "%*s${color}%*s${THEME[text_color]}%*s${THEME[border_color]}${THEME[v_line]}${THEME[text_color]}" \
                "$padding" "" \
                "$content_width" "$content" \
                "$padding" ""
            ;;
            
        center)
            # Center-aligned content
            # Calculate spaces needed on each side for centering
            local content_len
            content_len=$(get_display_length "$content")
            local spaces=$(( (content_width - content_len) / 2 ))
            local left_spaces=$(( padding + spaces ))
            local right_spaces=$(( padding + content_width - content_len - spaces ))
            
            # Format: [left_spaces][content][right_spaces][border]
            printf "%*s${color}%s${THEME[text_color]}%*s${THEME[border_color]}${THEME[v_line]}${THEME[text_color]}" \
                "$left_spaces" "" \
                "$content" \
                "$right_spaces" ""
            ;;
            
        *)
            # Left-aligned content (default)
            # Format: [padding][left-aligned content][padding][border]
            printf "%*s${color}%-*s${THEME[text_color]}%*s${THEME[border_color]}${THEME[v_line]}${THEME[text_color]}" \
                "$padding" "" \
                "$content_width" "$content" \
                "$padding" ""
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Table Element Rendering Function
# -----------------------------------------------------------------------------
# Renders table elements like titles and footers with proper positioning,
# borders, and formatting. This function handles the complex logic of
# positioning elements relative to the table and drawing appropriate borders.
#
# Parameters:
#   $1 - element_type: "title" or "footer"
#   $2 - total_table_width: Width of the main table
#
# Output:
#   Formatted title or footer with borders and proper positioning
# -----------------------------------------------------------------------------

render_table_element() {
    local element_type="$1"
    local total_table_width="$2"
    
    # Set up variables based on element type
    local element_text
    local element_position
    local element_width
    local color_theme
    
    if [[ "$element_type" == "title" ]]; then
        # Return early if no title is configured
        [[ -z "$TABLE_TITLE" ]] && return
        
        # Process title text (evaluate variables and color placeholders)
        element_text=$(eval echo "$TABLE_TITLE" 2>/dev/null)
        element_text=$(replace_color_placeholders "$element_text")
        element_text=$(printf '%b' "$element_text")
        
        element_position="$TITLE_POSITION"
        element_width="$TITLE_WIDTH"
        color_theme="${THEME[header_color]}"
    else
        # Return early if no footer is configured
        [[ -z "$TABLE_FOOTER" ]] && return
        
        # Process footer text (evaluate variables and color placeholders)
        element_text=$(eval echo "$TABLE_FOOTER" 2>/dev/null)
        element_text=$(replace_color_placeholders "$element_text")
        element_text=$(printf '%b' "$element_text")
        
        element_position="$FOOTER_POSITION"
        element_width="$FOOTER_WIDTH"
        color_theme="${THEME[footer_color]}"
    fi
    
    # Calculate horizontal offset based on position
    local offset=0
    case "$element_position" in
        left)
            offset=0
            ;;
        right)
            offset=$((total_table_width - element_width))
            ;;
        center)
            offset=$(((total_table_width - element_width) / 2))
            ;;
        full)
            offset=0
            ;;
        *)
            offset=0
            ;;
    esac
    
    # Render top border for titles
    if [[ "$element_type" == "title" ]]; then
        # Add leading spaces if needed
        [[ $offset -gt 0 ]] && printf "%*s" "$offset" ""
        
        # Draw top border
        printf "${THEME[border_color]}%s" "${THEME[tl_corner]}"
        printf "${THEME[h_line]}%.0s" $(seq 1 "$element_width")
        printf "%s${THEME[text_color]}\n" "${THEME[tr_corner]}"
    fi
    
    # Render the main content line
    [[ $offset -gt 0 ]] && printf "%*s" "$offset" ""
    printf "${THEME[border_color]}%s${THEME[text_color]}" "${THEME[v_line]}"
    
    # Calculate available width for text content
    local available_width=$((element_width - (2 * DEFAULT_PADDING)))
    
    # Clip text if it's too long
    element_text=$(clip_text "$element_text" "$available_width" "$element_position")
    
    # Render content based on position
    case "$element_position" in
        left)
            printf "%*s${color_theme}%-*s${THEME[text_color]}%*s" \
                "$DEFAULT_PADDING" "" \
                "$available_width" "$element_text" \
                "$DEFAULT_PADDING" ""
            ;;
        right)
            printf "%*s${color_theme}%*s${THEME[text_color]}%*s" \
                "$DEFAULT_PADDING" "" \
                "$available_width" "$element_text" \
                "$DEFAULT_PADDING" ""
            ;;
        center)
            local element_len
            element_len=$(get_display_length "$element_text")
            printf "%*s${color_theme}%s${THEME[text_color]}%*s" \
                "$DEFAULT_PADDING" "" \
                "$element_text" \
                "$((available_width - element_len + DEFAULT_PADDING))" ""
            ;;
        full)
            # Full-width positioning with centered text
            local text_len
            text_len=$(get_display_length "$element_text")
            local spaces=$(( (available_width - text_len) / 2 ))
            local left_spaces=$(( DEFAULT_PADDING + spaces ))
            local right_spaces=$(( DEFAULT_PADDING + available_width - text_len - spaces ))
            printf "%*s${color_theme}%s${THEME[text_color]}%*s" \
                "$left_spaces" "" \
                "$element_text" \
                "$right_spaces" ""
            ;;
        *)
            # Default positioning
            printf "%*s${color_theme}%s${THEME[text_color]}%*s" \
                "$DEFAULT_PADDING" "" \
                "$element_text" \
                "$DEFAULT_PADDING" ""
            ;;
    esac
    
    # Close the content line
    printf "${THEME[border_color]}%s${THEME[text_color]}\n" "${THEME[v_line]}"
    
    # Render bottom border for footers
    if [[ "$element_type" == "footer" ]]; then
        # Add leading spaces if needed
        [[ $offset -gt 0 ]] && printf "%*s" "$offset" ""
        
        # Draw bottom border
        echo -ne "${THEME[border_color]}${THEME[bl_corner]}"
        for i in $(seq 1 "$element_width"); do
            echo -ne "${THEME[h_line]}"
        done
        echo -ne "${THEME[br_corner]}${THEME[text_color]}\n"
    fi
}

# =============================================================================
# tables.sh - Library for JSON to ANSI tables
# Section 09: Border and Table Structure Rendering
# =============================================================================
# This section handles the rendering of table borders, headers, and structural
# elements. It includes complex logic for drawing borders that accommodate
# titles and footers, rendering column headers, and creating separators
# between different sections of the table.
# =============================================================================

# -----------------------------------------------------------------------------
# Border Character Selection Function
# -----------------------------------------------------------------------------
# Returns the appropriate border characters for top or bottom borders.
# This helper function centralizes the logic for selecting corner and
# junction characters based on border position.
#
# Parameters:
#   $1 - border_type: "top" or "bottom"
#
# Returns:
#   Three space-separated values: left_corner right_corner junction_char
# -----------------------------------------------------------------------------

get_border_chars() {
    local border_type="$1"
    
    if [[ "$border_type" == "top" ]]; then
        # Top border uses top corners and top junctions
        echo "${THEME[tl_corner]} ${THEME[tr_corner]} ${THEME[t_junct]}"
    else
        # Bottom border uses bottom corners and bottom junctions
        echo "${THEME[bl_corner]} ${THEME[br_corner]} ${THEME[b_junct]}"
    fi
}

# -----------------------------------------------------------------------------
# Generic Table Border Rendering Function
# -----------------------------------------------------------------------------
# Renders complex table borders that can accommodate titles and footers.
# This function handles the intricate logic of drawing borders that may
# need to connect with or accommodate external elements.
#
# Parameters:
#   $1 - border_type: "top" or "bottom"
#   $2 - total_table_width: Width of the main table
#   $3 - element_offset: Horizontal offset of title/footer
#   $4 - element_right_edge: Right edge position of title/footer
#   $5 - element_width: Width of title/footer element
#
# Output:
#   A complete border line with appropriate junctions and connections
# -----------------------------------------------------------------------------

render_table_border() {
    local border_type="$1"
    local total_table_width="$2"
    local element_offset="$3"
    local element_right_edge="$4"
    local element_width="$5"
    
    # Calculate column separator positions
    # These are the positions where vertical lines between columns appear
    local column_widths_sum=0
    local column_positions=()
    
    # Build array of column separator positions
    for ((i=0; i<COLUMN_COUNT-1; i++)); do
        if [[ "${VISIBLES[i]}" == "true" ]]; then
            column_widths_sum=$((column_widths_sum + WIDTHS[i]))
            
            # Check if there are more visible columns after this one
            local has_more_visible=false
            for ((j=$((i+1)); j<COLUMN_COUNT; j++)); do
                [[ "${VISIBLES[j]}" == "true" ]] && has_more_visible=true && break
            done
            
            # Add separator position if there are more visible columns
            [[ "$has_more_visible" == "true" ]] && column_positions+=("$column_widths_sum") && ((column_widths_sum++))
        fi
    done
    
    # Determine the maximum width needed for the border
    local max_width=$((total_table_width + 2))  # +2 for left and right borders
    
    # Extend width if title/footer is wider than the table
    [[ -n "$element_width" && $element_width -gt 0 && $((element_width + 2)) -gt $max_width ]] && max_width=$((element_width + 2))
    
    # Get the appropriate border characters
    read -r left_char right_char junction_char <<< "$(get_border_chars "$border_type")"
    
    # Special case: if element starts at position 0, use a junction instead of corner
    [[ -n "$element_width" && $element_width -gt 0 && $element_offset -eq 0 ]] && left_char="${THEME[l_junct]}"
    
    # Build the border string character by character
    local border_string=""
    for ((i=0; i<max_width; i++)); do
        local char_to_print="${THEME[h_line]}"  # Default to horizontal line
        
        if [[ $i -eq 0 ]]; then
            # First character - use left corner/junction
            char_to_print="$left_char"
            
        elif [[ $i -eq $((max_width - 1)) ]]; then
            # Last character - determine right corner/junction based on element position
            if [[ -n "$element_width" && $element_width -gt 0 && $element_right_edge -gt $total_table_width ]]; then
                # Element extends beyond table - use opposite corner
                char_to_print=$(if [[ "$border_type" == "top" ]]; then echo "${THEME[br_corner]}"; else echo "${THEME[tr_corner]}"; fi)
            elif [[ -n "$element_width" && $element_width -gt 0 && $element_right_edge -eq $total_table_width ]]; then
                # Element aligns with table edge - use right junction
                char_to_print="${THEME[r_junct]}"
            else
                # Normal case - use right corner
                char_to_print="$right_char"
            fi
            
        else
            # Middle characters - check for column separators and element boundaries
            
            # Check if this position is a column separator
            for pos in "${column_positions[@]}"; do
                [[ $((pos + 1)) -eq $i ]] && char_to_print="$junction_char" && break
            done
            
            # Handle element boundary intersections
            if [[ -n "$element_width" && $element_width -gt 0 ]]; then
                if [[ $i -eq $element_offset && $element_offset -gt 0 && $element_offset -lt $((total_table_width + 1)) ]] || 
                   [[ $i -eq $((element_right_edge + 1)) && $((element_right_edge + 1)) -lt $((total_table_width + 1)) ]]; then
                    
                    # Check if this position is also a column line
                    local is_column_line=false
                    for pos in "${column_positions[@]}"; do
                        [[ $((pos + 1)) -eq $i ]] && is_column_line=true && break
                    done
                    
                    if [[ "$is_column_line" == "true" ]]; then
                        # Intersection of element boundary and column line - use cross
                        char_to_print="${THEME[cross]}"
                    else
                        # Element boundary only - use appropriate junction
                        char_to_print=$(if [[ "$border_type" == "top" ]]; then echo "${THEME[b_junct]}"; else echo "${THEME[t_junct]}"; fi)
                    fi
                    
                elif [[ $i -eq $((total_table_width + 1)) && $i -lt $((max_width - 1)) && $element_right_edge -gt $((total_table_width - 1)) ]]; then
                    # Element extends beyond table boundary
                    char_to_print=$(if [[ "$border_type" == "top" ]]; then echo "${THEME[t_junct]}"; else echo "${THEME[b_junct]}"; fi)
                fi
            fi
        fi
        
        border_string+="$char_to_print"
    done
    
    # Output the complete border line
    printf "${THEME[border_color]}%s${THEME[text_color]}\n" "$border_string"
}

# -----------------------------------------------------------------------------
# Top Border Rendering Function
# -----------------------------------------------------------------------------
# Renders the top border of the table, taking into account any title
# positioning and dimensions.
#
# Output:
#   Complete top border with appropriate title accommodations
# -----------------------------------------------------------------------------

render_table_top_border() {
    local total_table_width
    total_table_width=$(calculate_table_width)
    
    # Initialize title positioning variables
    local title_offset=0
    local title_right_edge=0
    local title_width=""
    local title_position="none"
    
    # Calculate title positioning if a title exists
    if [[ -n "$TABLE_TITLE" ]]; then
        title_width=$TITLE_WIDTH
        title_position=$TITLE_POSITION
        
        case "$TITLE_POSITION" in
            left)
                title_offset=0
                title_right_edge=$TITLE_WIDTH
                ;;
            right)
                title_offset=$((total_table_width - TITLE_WIDTH))
                title_right_edge=$total_table_width
                ;;
            center)
                title_offset=$(((total_table_width - TITLE_WIDTH) / 2))
                title_right_edge=$((title_offset + TITLE_WIDTH))
                ;;
            full)
                title_offset=0
                title_right_edge=$total_table_width
                ;;
            *)
                title_offset=0
                title_right_edge=$TITLE_WIDTH
                ;;
        esac
    fi
    
    # Render the border with title accommodations
    render_table_border "top" "$total_table_width" "$title_offset" "$title_right_edge" "$title_width" "$title_position" "$([[ "$title_position" == "full" ]] && echo true || echo false)"
}

# -----------------------------------------------------------------------------
# Bottom Border Rendering Function
# -----------------------------------------------------------------------------
# Renders the bottom border of the table, taking into account any footer
# positioning and dimensions.
#
# Output:
#   Complete bottom border with appropriate footer accommodations
# -----------------------------------------------------------------------------

render_table_bottom_border() {
    local total_table_width
    total_table_width=$(calculate_table_width)
    
    # Initialize footer positioning variables
    local footer_offset=0
    local footer_right_edge=0
    local footer_width=""
    local footer_position="none"
    
    # Calculate footer positioning if a footer exists
    if [[ -n "$TABLE_FOOTER" ]]; then
        footer_width=$FOOTER_WIDTH
        footer_position=$FOOTER_POSITION
        
        case "$FOOTER_POSITION" in
            left)
                footer_offset=0
                footer_right_edge=$FOOTER_WIDTH
                ;;
            right)
                footer_offset=$((total_table_width - FOOTER_WIDTH))
                footer_right_edge=$total_table_width
                ;;
            center)
                footer_offset=$(((total_table_width - FOOTER_WIDTH) / 2))
                footer_right_edge=$((footer_offset + FOOTER_WIDTH))
                ;;
            full)
                footer_offset=0
                footer_right_edge=$total_table_width
                ;;
            *)
                footer_offset=0
                footer_right_edge=$FOOTER_WIDTH
                ;;
        esac
    fi
    
    # Render the border with footer accommodations
    render_table_border "bottom" "$total_table_width" "$footer_offset" "$footer_right_edge" "$footer_width" "$footer_position" "$([[ "$footer_position" == "full" ]] && echo true || echo false)"
}

# -----------------------------------------------------------------------------
# Table Headers Rendering Function
# -----------------------------------------------------------------------------
# Renders the column headers with proper formatting, alignment, and colors.
# This function handles clipping of header text that exceeds column width.
#
# Output:
#   Complete header row with all visible column headers
# -----------------------------------------------------------------------------

render_table_headers() {
    # Start the header row with left border
    printf "${THEME[border_color]}%s${THEME[text_color]}" "${THEME[v_line]}"
    
    # Render each visible column header
    for ((i=0; i<COLUMN_COUNT; i++)); do
        local visible="${VISIBLES[i]}"
        
        if [[ "$visible" == "true" ]]; then
            local header_text="${HEADERS[$i]}"
            local width="${WIDTHS[i]}"
            local padding="${PADDINGS[i]}"
            local justification="${JUSTIFICATIONS[$i]}"
            
            # Calculate available width for header text
            local content_width=$((width - (2 * padding)))
            
            # Clip header text if it's too long
            header_text=$(clip_text "$header_text" "$content_width" "$justification")
            
            # Render the header cell
            render_cell "$header_text" "$width" "$padding" "$justification" "${THEME[caption_color]}"
        fi
    done
    
    # End the header row
    printf "\n"
}

# -----------------------------------------------------------------------------
# Table Separator Rendering Function
# -----------------------------------------------------------------------------
# Renders horizontal separators between table sections (header/data, data/summary).
# This function creates lines with appropriate junctions at column boundaries.
#
# Parameters:
#   $1 - type: "middle" for regular separators, "bottom" for final separator
#
# Output:
#   Complete separator line with proper junctions
# -----------------------------------------------------------------------------

render_table_separator() {
    local type="$1"
    
    # Select appropriate characters based on separator type
    local left_char="${THEME[l_junct]}"
    local right_char="${THEME[r_junct]}"
    local middle_char="${THEME[cross]}"
    
    # Bottom separators use different characters
    [[ "$type" == "bottom" ]] && left_char="${THEME[bl_corner]}" && right_char="${THEME[br_corner]}" && middle_char="${THEME[b_junct]}"
    
    # Start with left junction/corner
    printf "${THEME[border_color]}%s" "${left_char}"
    
    # Draw horizontal lines for each visible column
    for ((i=0; i<COLUMN_COUNT; i++)); do
        if [[ "${VISIBLES[i]}" == "true" ]]; then
            local width=${WIDTHS[i]}
            
            # Draw horizontal line for this column's width
            for ((j=0; j<width; j++)); do
                printf "%s" "${THEME[h_line]}"
            done
            
            # Add junction between columns (if not the last column)
            if [[ $i -lt $((COLUMN_COUNT-1)) ]]; then
                # Check if there are more visible columns
                local next_visible=false
                for ((k=$((i+1)); k<COLUMN_COUNT; k++)); do
                    if [[ "${VISIBLES[k]}" == "true" ]]; then
                        next_visible=true
                        break
                    fi
                done
                
                # Add junction character if there are more visible columns
                [[ "$next_visible" == "true" ]] && printf "%s" "${middle_char}"
            fi
        fi
    done
    
    # End with right junction/corner
    printf "%s${THEME[text_color]}\n" "${right_char}"
}

# =============================================================================
# tables.sh - Library for JSON to ANSI tables
# Section 10: Data Row Rendering Functions
# =============================================================================
# This section handles the rendering of actual data rows, including complex
# features like multi-line rows, text wrapping, break detection between rows,
# and proper formatting of different data types. This is one of the most
# complex parts of the system.
# =============================================================================

# -----------------------------------------------------------------------------
# Main Data Rows Rendering Function
# -----------------------------------------------------------------------------
# Renders all data rows with support for multi-line content, text wrapping,
# break detection, and proper cell formatting. This function handles the
# most complex rendering logic in the entire system.
#
# Side Effects:
#   Outputs formatted table rows to stdout
# -----------------------------------------------------------------------------

render_data_rows() {
    # Return early if no data to render
    [[ ${#DATA_ROWS[@]} -eq 0 ]] && return
    
    # Track values for break detection
    # Break values are used to insert separators when certain column values change
    local last_break_values=()
    for ((j=0; j<COLUMN_COUNT; j++)); do
        last_break_values[j]=""
    done
    
    # Process each row of data
    for ((row_idx=0; row_idx<${#DATA_ROWS[@]}; row_idx++)); do
        # Recreate the associative array from serialized data
        eval "${DATA_ROWS[$row_idx]}"
        
        # Check if we need to insert a break before this row
        local needs_break=false
        for ((j=0; j<COLUMN_COUNT; j++)); do
            if [[ "${BREAKS[$j]}" == "true" ]]; then
                local key="${KEYS[$j]}"
                local value="${row_data[$key]}"
                
                # Insert break if this column's value changed from the last row
                if [[ -n "${last_break_values[$j]}" && "$value" != "${last_break_values[$j]}" ]]; then
                    needs_break=true
                    break
                fi
            fi
        done
        
        # Render break separator if needed
        if [[ "$needs_break" == "true" ]]; then
            render_table_separator "middle"
        fi
        
        # Prepare multi-line content for this row
        # This associative array stores content for each line of each column
        local -A line_values
        local row_line_count=1  # Track the number of lines in this row
        
        # Process each column to prepare display values and handle wrapping
        for ((j=0; j<COLUMN_COUNT; j++)); do
            local key="${KEYS[$j]}"
            local value="${row_data[$key]}"
            
            # Format the value for display
            local display_value
            if [[ "${DATATYPES[j]}" == "float" ]]; then
                # Special handling for float datatype
                local validate_fn="${DATATYPE_HANDLERS[${DATATYPES[j]}_validate]}"
                local validated_value
                validated_value=$("$validate_fn" "$value")
                
                if [[ "$validated_value" == "null" ]]; then
                    case "${NULL_VALUES[j]}" in
                        0) display_value="0" ;;
                        missing) display_value="Missing" ;;
                        *) display_value="" ;;
                    esac
                elif [[ "$validated_value" == "0" ]]; then
                    case "${ZERO_VALUES[j]}" in
                        0) display_value="0" ;;
                        missing) display_value="Missing" ;;
                        *) display_value="" ;;
                    esac
                else
                    display_value=$(format_float "$validated_value" "${FORMATS[j]}" "$j")
                fi
            else
                # Standard formatting for other datatypes
                display_value=$(format_display_value "$value" "${NULL_VALUES[j]}" "${ZERO_VALUES[j]}" "${DATATYPES[j]}" "${FORMATS[j]}" "${STRING_LIMITS[j]}" "${WRAP_MODES[j]}" "${WRAP_CHARS[j]}")
            fi
            
            # Handle text wrapping based on wrap mode and wrap character
            if [[ -n "${WRAP_CHARS[$j]}" && "${WRAP_MODES[$j]}" == "wrap" && -n "$display_value" && "$value" != "null" ]]; then
                # Character-based wrapping (split on specific character)
                local IFS="${WRAP_CHARS[$j]}"
                read -ra parts <<<"$display_value"
                
                # Process each part and clip if necessary
                for k in "${!parts[@]}"; do
                    local part="${parts[k]}"
                    local content_width=$((WIDTHS[j] - (2 * PADDINGS[j])))
                    local part_len
                    part_len=$(get_display_length "$part")
                    
                    # Clip part if it exceeds column width
                    if [[ $part_len -gt $content_width ]]; then
                        case "${JUSTIFICATIONS[$j]}" in
                            right)
                                part="${part: -${content_width}}"
                                ;;
                            center)
                                local excess=$(( part_len - content_width ))
                                local left_clip=$(( excess / 2 ))
                                part="${part:${left_clip}:${content_width}}"
                                ;;
                            *)
                                part="${part:0:${content_width}}"
                                ;;
                        esac
                    fi
                    
                    # Store the processed part
                    line_values[$j,$k]="$part"
                done
                
                # Update row line count if this column has more lines
                [[ ${#parts[@]} -gt $row_line_count ]] && row_line_count=${#parts[@]}
                
            elif [[ "${WRAP_MODES[$j]}" == "wrap" && -n "$display_value" && "$value" != "null" ]]; then
                # Word-based wrapping (split on spaces)
                local content_width=$((WIDTHS[j] - (2 * PADDINGS[j])))
                local words=()
                IFS=' ' read -ra words <<<"$display_value"
                
                local current_line=""
                local line_index=0
                
                # Build wrapped lines by adding words until width limit is reached
                for word in "${words[@]}"; do
                    if [[ -z "$current_line" ]]; then
                        # First word on the line
                        current_line="$word"
                    elif [[ $(( ${#current_line} + ${#word} + 1 )) -le $content_width ]]; then
                        # Word fits on current line
                        current_line="$current_line $word"
                    else
                        # Word doesn't fit - start new line
                        line_values[$j,$line_index]="$current_line"
                        current_line="$word"
                        ((line_index++))
                    fi
                done
                
                # Store the last line if it has content
                if [[ -n "$current_line" ]]; then
                    line_values[$j,$line_index]="$current_line"
                    ((line_index++))
                fi
                
                # Update row line count
                [[ $line_index -gt $row_line_count ]] && row_line_count=$line_index
                
            else
                # No wrapping - handle single line with potential clipping
                local content_width=$((WIDTHS[j] - (2 * PADDINGS[j])))
                local display_len
                display_len=$(get_display_length "$display_value")
                
                # Clip if content exceeds available width
                if [[ $display_len -gt $content_width ]]; then
                    case "${JUSTIFICATIONS[$j]}" in
                        right)
                            display_value="${display_value: -${content_width}}"
                            ;;
                        center)
                            local excess=$(( display_len - content_width ))
                            local left_clip=$(( excess / 2 ))
                            display_value="${display_value:${left_clip}:${content_width}}"
                            ;;
                        *)
                            display_value="${display_value:0:${content_width}}"
                            ;;
                    esac
                fi
                
                # Store the single line value
                line_values[$j,0]="$display_value"
            fi
        done
        
        # Render each line of this multi-line row
        for ((line=0; line<row_line_count; line++)); do
            # Start the line with left border
            printf "${THEME[border_color]}%s${THEME[text_color]}" "${THEME[v_line]}"
            
            # Render each visible column for this line
            for ((j=0; j<COLUMN_COUNT; j++)); do
                if [[ "${VISIBLES[j]}" == "true" ]]; then
                    local display_value="${line_values[$j,$line]:-}"
                    local content_width=$((WIDTHS[j] - (2 * PADDINGS[j])))
                    
                    # Additional clipping for explicitly specified widths
                    # This ensures content never exceeds specified column widths
                    local display_value_len
                    display_value_len=$(get_display_length "$display_value")
                    if [[ $display_value_len -gt $content_width && "${IS_WIDTH_SPECIFIED[j]}" == "true" ]]; then
                        case "${JUSTIFICATIONS[$j]}" in
                            right)
                                display_value="${display_value: -$content_width}"
                                ;;
                            center)
                                local excess=$(( display_value_len - content_width ))
                                local left_clip=$(( excess / 2 ))
                                display_value="${display_value:$left_clip:$content_width}"
                                ;;
                            *)
                                display_value="${display_value:0:$content_width}"
                                ;;
                        esac
                    fi
                    
                    # Render the cell
                    render_cell "$display_value" "${WIDTHS[j]}" "${PADDINGS[j]}" "${JUSTIFICATIONS[j]}" "${THEME[text_color]}"
                fi
            done
            
            # End the line
            printf "\n"
        done
        
        # Update break tracking values for the next row
        for ((j=0; j<COLUMN_COUNT; j++)); do
            if [[ "${BREAKS[$j]}" == "true" ]]; then
                local key="${KEYS[$j]}"
                local value="${row_data[$key]}"
                last_break_values[j]="$value"
            fi
        done
    done
}

# =============================================================================
# tables.sh - Library for JSON to ANSI tables
# Section 11: Summary Rendering Functions
# =============================================================================
# This section handles the rendering of summary rows that appear at the bottom
# of tables. Summary rows display calculated statistics like sums, averages,
# counts, etc. for each column that has summary calculations enabled.
# =============================================================================

# -----------------------------------------------------------------------------
# Summary Row Rendering Function
# -----------------------------------------------------------------------------
# Renders the summary row at the bottom of the table if any columns have
# summary calculations enabled. This function checks for the presence of
# summaries, renders a separator line, and then displays the summary values
# with proper formatting and alignment.
#
# Returns:
#   0 if summaries were rendered, 1 if no summaries exist
#
# Output:
#   Summary row with calculated values, or nothing if no summaries configured
# -----------------------------------------------------------------------------

render_summaries_row() {
    # First, check if any columns have summaries enabled
    local has_summaries=false
    for ((i=0; i<COLUMN_COUNT; i++)); do
        [[ "${SUMMARIES[$i]}" != "none" ]] && has_summaries=true && break
    done
    
    # If no summaries are configured, return without rendering anything
    if [[ "$has_summaries" == true ]]; then
        # Render separator line before summary row
        render_table_separator "middle"
        
        # Start the summary row with left border
        printf "${THEME[border_color]}%s${THEME[text_color]}" "${THEME[v_line]}"
        
        # Render each visible column's summary value
        for ((i=0; i<COLUMN_COUNT; i++)); do
            if [[ "${VISIBLES[i]}" == "true" ]]; then
                # Get the formatted summary value for this column
                local summary_value
                summary_value=$(format_summary_value "$i" "${SUMMARIES[$i]}" "${DATATYPES[$i]}" "${FORMATS[$i]}")
                
                # Calculate available width for the summary value
                local content_width=$((WIDTHS[i] - (2 * PADDINGS[i])))
                
                # Clip summary value if it exceeds column width and width is explicitly specified
                # This ensures summary values don't break the table layout
                local summary_value_len
                summary_value_len=$(get_display_length "$summary_value")
                if [[ $summary_value_len -gt $content_width && "${IS_WIDTH_SPECIFIED[i]}" == "true" ]]; then
                    case "${JUSTIFICATIONS[$i]}" in
                        right)
                            # Right-aligned clipping: keep rightmost characters
                            summary_value="${summary_value: -$content_width}"
                            ;;
                        center)
                            # Center-aligned clipping: remove equal amounts from both sides
                            local excess=$(( summary_value_len - content_width ))
                            local left_clip=$(( excess / 2 ))
                            summary_value="${summary_value:$left_clip:$content_width}"
                            ;;
                        *)
                            # Left-aligned clipping: keep leftmost characters
                            summary_value="${summary_value:0:$content_width}"
                            ;;
                    esac
                fi
                
                # Render the summary cell with special summary color theme
                render_cell "$summary_value" "${WIDTHS[i]}" "${PADDINGS[i]}" "${JUSTIFICATIONS[i]}" "${THEME[summary_color]}"
            fi
        done
        
        # End the summary row
        printf "\n"
        return 0
    fi
    
    # No summaries were rendered
    return 1
}

# =============================================================================
# tables.sh - Library for JSON to ANSI tables
# Section 12: Main Functions and Public API
# =============================================================================
# This section contains the main orchestration function that coordinates all
# the table rendering components, as well as the public API functions that
# users can call. It also handles command-line argument processing and
# function exports for when the script is sourced as a library.
# =============================================================================

# -----------------------------------------------------------------------------
# Main Table Drawing Function
# -----------------------------------------------------------------------------
# This is the primary orchestration function that coordinates all aspects of
# table rendering. It processes command-line arguments, validates inputs,
# parses configuration, processes data, and renders the complete table.
#
# Parameters:
#   $1 - layout_file: Path to the JSON layout configuration file
#   $2 - data_file: Path to the JSON data file
#   Additional parameters are processed as command-line options
#
# Returns:
#   0 on success, 1 on error
#
# Output:
#   Complete formatted table to stdout, or help/version information
# -----------------------------------------------------------------------------

draw_table() {
    local layout_file="$1"
    local data_file="$2"
    
    # Handle special command-line options
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        show_help
        return 0
    fi
    
    if [[ "$1" == "--version" ]]; then
        echo "tables.sh version $TABLES_VERSION"
        return 0
    fi
    
    # Show help if no arguments provided
    if [[ $# -eq 0 ]]; then
        show_help
        return 0
    fi
    
    # Validate required arguments
    if [[ -z "$layout_file" || -z "$data_file" ]]; then
        echo "Error: Both layout and data files are required" >&2
        echo "Use --help for usage information" >&2
        return 1
    fi
    
    # Skip the first two arguments (layout and data files)
    shift 2
    
    # Process additional command-line options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            *)
                echo "Error: Unknown option: $1" >&2
                echo "Use --help for usage information" >&2
                return 1
                ;;
        esac
    done
    
    # Validate input files exist and are readable
    validate_input_files "$layout_file" "$data_file" || return 1
    
    # Parse the layout configuration
    parse_layout_file "$layout_file" || return 1
    
    # Initialize the theme based on configuration
    get_theme "$THEME_NAME"
    
    # Initialize summary tracking arrays
    initialize_summaries
    
    # Load and prepare data from JSON file
    prepare_data "$data_file"
    
    # Sort data according to configuration
    sort_data
    
    # Process data rows and calculate column widths
    process_data_rows
    
    # Calculate total table width for layout purposes
    local total_table_width
    total_table_width=$(calculate_table_width)
    
    # Calculate title and footer dimensions if they exist
    if [[ -n "$TABLE_TITLE" ]]; then
        calculate_title_width "$TABLE_TITLE" "$total_table_width"
    fi
    
    if [[ -n "$TABLE_FOOTER" ]]; then
        calculate_footer_width "$TABLE_FOOTER" "$total_table_width"
    fi
    
    # Render the complete table structure
    # 1. Title (if configured)
    [[ -n "$TABLE_TITLE" ]] && render_table_element "title" "$total_table_width"
    
    # 2. Top border
    render_table_top_border
    
    # 3. Column headers
    render_table_headers
    
    # 4. Separator between headers and data
    render_table_separator "middle"
    
    # 5. Data rows
    render_data_rows "$MAX_LINES"
    
    # 6. Summary row (if any summaries are configured)
    local has_summaries=false
    render_summaries_row && has_summaries=true
    
    # 7. Bottom border
    render_table_bottom_border
    
    # 8. Footer (if configured)
    [[ -n "$TABLE_FOOTER" ]] && render_table_element "footer" "$total_table_width"
}

# -----------------------------------------------------------------------------
# Public API Functions
# -----------------------------------------------------------------------------
# These functions provide the public interface for the tables.sh library.
# They can be called directly or used when the script is sourced.
# -----------------------------------------------------------------------------

# Main entry point function
tables_main() {
    draw_table "$@"
}

# Standard rendering function with explicit parameters
tables_render() {
    local layout_file="$1"
    local data_file="$2"
    shift 2
    draw_table "$layout_file" "$data_file" "$@"
}

# Render from JSON strings instead of files
tables_render_from_json() {
    local layout_json="$1"
    local data_json="$2"
    shift 2
    
    # Create temporary files for the JSON content
    local temp_layout
    local temp_data
    temp_layout=$(mktemp)
    temp_data=$(mktemp)
    
    # Ensure cleanup of temporary files
    trap 'rm -f "$temp_layout" "$temp_data"' RETURN
    
    # Write JSON content to temporary files
    echo "$layout_json" > "$temp_layout"
    echo "$data_json" > "$temp_data"
    
    # Render using the temporary files
    draw_table "$temp_layout" "$temp_data" "$@"
}

# Get available themes
tables_get_themes() {
    echo "Available themes: Red, Blue"
}

# Get version information
tables_version() {
    echo "$TABLES_VERSION"
}

# Reset all global state (useful for testing or multiple renders)
tables_reset() {
    # Reset basic configuration
    COLUMN_COUNT=0
    MAX_LINES=1
    THEME_NAME="Red"
    
    # Reset title and footer
    TABLE_TITLE=""
    TITLE_WIDTH=0
    TITLE_POSITION="none"
    TABLE_FOOTER=""
    FOOTER_WIDTH=0
    FOOTER_POSITION="none"
    
    # Reset column configuration arrays
    HEADERS=()
    KEYS=()
    JUSTIFICATIONS=()
    DATATYPES=()
    NULL_VALUES=()
    ZERO_VALUES=()
    FORMATS=()
    SUMMARIES=()
    IS_WIDTH_SPECIFIED=()
    VISIBLES=()
    BREAKS=()
    STRING_LIMITS=()
    WRAP_MODES=()
    WRAP_CHARS=()
    PADDINGS=()
    WIDTHS=()
    
    # Reset sorting configuration
    SORT_KEYS=()
    SORT_DIRECTIONS=()
    SORT_PRIORITIES=()
    
    # Reset data arrays
    ROW_JSONS=()
    DATA_ROWS=()
    
    # Reset summary arrays
    SUM_SUMMARIES=()
    COUNT_SUMMARIES=()
    MIN_SUMMARIES=()
    MAX_SUMMARIES=()
    UNIQUE_VALUES=()
    AVG_SUMMARIES=()
    AVG_COUNTS=()
    
    # Reinitialize theme
    get_theme "$THEME_NAME"
}

# -----------------------------------------------------------------------------
# Script Execution Logic
# -----------------------------------------------------------------------------
# This section determines whether the script is being executed directly
# or sourced as a library, and handles each case appropriately.
# -----------------------------------------------------------------------------

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    # Script is being sourced - export functions for library use
    export -f tables_render tables_render_from_json tables_get_themes tables_version tables_reset draw_table get_theme format_with_commas get_display_length
else
    # Script is being executed directly - run main function with arguments
    tables_main "$@"
fi