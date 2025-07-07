/*
 * tables.c - Main entry point for the tables utility in C
 * This program converts JSON data into ANSI-formatted tables for terminal output.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <jansson.h>
#include "tables_config.h"
#include "tables_themes.h"
#include "tables_data.h"
#include "tables_render.h"

#define VERSION "0.1.0"

/* Function prototypes */
void print_help(void);
void print_version(void);

/*
 * Main function
 * Handles command-line arguments and coordinates the execution flow.
 */
int main(int argc, char *argv[]) {
    if (argc < 3) {
        fprintf(stderr, "Error: Both layout and data JSON files are required\n");
        print_help();
        return 1;
    }

    if (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0) {
        print_help();
        return 0;
    }

    if (strcmp(argv[1], "--version") == 0) {
        print_version();
        return 0;
    }

    const char *layout_file = argv[1];
    const char *data_file = argv[2];

    // Validate input files
    if (validate_input_files(layout_file, data_file) != 0) {
        fprintf(stderr, "Error: Input file validation failed\n");
        return 1;
    }

    // Parse layout file
    TableConfig config;
    if (parse_layout_file(layout_file, &config) != 0) {
        fprintf(stderr, "Error: Failed to parse layout file %s\n", layout_file);
        return 1;
    }

    // Set the theme based on configuration
    get_theme(&config);

    // Load and prepare data
    TableData table_data;
    if (prepare_data(data_file, &config, &table_data) != 0) {
        fprintf(stderr, "Error: Failed to load data from %s\n", data_file);
        free_table_config(&config);
        return 1;
    }

    // Sort data if specified
    sort_data(&config, &table_data);

    // Process data rows and calculate summaries
    process_data_rows(&config, &table_data);

    // Render table
    render_table(&config, &table_data);

    // Clean up data
    free_table_data(&table_data, config.column_count);

    // Clean up
    free_table_config(&config);

    return 0;
}

/*
 * Print help message
 */
void print_help(void) {
    printf("Usage: tables <layout_json_file> <data_json_file> [OPTIONS]\n");
    printf("Parameters:\n");
    printf("  layout_json_file: JSON file defining table structure and formatting\n");
    printf("  data_json_file: JSON file containing the data to display\n");
    printf("Options:\n");
    printf("  --debug: Enable debug output to stderr\n");
    printf("  --version: Display version information\n");
    printf("  --help, -h: Show this help message\n");
}

/*
 * Print version information
 */
void print_version(void) {
    printf("tables version %s\n", VERSION);
}
