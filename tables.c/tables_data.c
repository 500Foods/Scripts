/*
 * tables_data.c - Implementation of data processing for the tables utility
 * Handles loading, sorting, and summarizing data from JSON files.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <jansson.h>
#include "tables_data.h"

/*
 * Helper function to duplicate a string, returning NULL if input is NULL
 */
static char *strdup_safe(const char *str) {
    if (str == NULL) return NULL;
    char *dup = strdup(str);
    if (dup == NULL) {
        fprintf(stderr, "Error: Memory allocation failed for string duplication\n");
        return NULL;
    }
    return dup;
}

/*
 * Load and prepare data from JSON file
 */
int prepare_data(const char *data_file, TableConfig *config, TableData *data) {
    json_t *root;
    json_error_t error;
    FILE *fp;
    char *buffer = NULL;
    size_t buffer_size = 0;
    size_t total_read = 0;
    size_t chunk_size = 1024;
    
    fp = fopen(data_file, "r");
    if (fp == NULL) {
        fprintf(stderr, "Error: Cannot open data file %s\n", data_file);
        return 1;
    }
    
    // Read file content into buffer
    buffer = malloc(chunk_size);
    if (buffer == NULL) {
        fprintf(stderr, "Error: Memory allocation failed for buffer\n");
        fclose(fp);
        return 1;
    }
    
    while (1) {
        size_t bytes_read = fread(buffer + total_read, 1, chunk_size, fp);
        total_read += bytes_read;
        if (bytes_read < chunk_size) {
            if (feof(fp)) break;
            if (ferror(fp)) {
                fprintf(stderr, "Error: Reading data file %s\n", data_file);
                free(buffer);
                fclose(fp);
                return 1;
            }
        }
        buffer_size += chunk_size;
        char *new_buffer = realloc(buffer, buffer_size);
        if (new_buffer == NULL) {
            fprintf(stderr, "Error: Memory reallocation failed for buffer\n");
            free(buffer);
            fclose(fp);
            return 1;
        }
        buffer = new_buffer;
    }
    fclose(fp);
    
    // Null-terminate the buffer
    buffer[total_read] = '\0';
    
    // Parse JSON
    root = json_loads(buffer, 0, &error);
    free(buffer);
    if (root == NULL) {
        fprintf(stderr, "Error: JSON parsing failed for %s: %s\n", data_file, error.text);
        return 1;
    }
    
    if (!json_is_array(root)) {
        fprintf(stderr, "Error: Data JSON root must be an array\n");
        json_decref(root);
        return 1;
    }
    
    // Initialize TableData structure
    memset(data, 0, sizeof(TableData));
    data->row_count = json_array_size(root);
    data->rows = malloc(data->row_count * sizeof(DataRow));
    if (data->rows == NULL && data->row_count > 0) {
        fprintf(stderr, "Error: Memory allocation failed for data rows\n");
        json_decref(root);
        return 1;
    }
    
    // Allocate summaries array
    data->summaries = malloc(config->column_count * sizeof(SummaryStats));
    if (data->summaries == NULL) {
        fprintf(stderr, "Error: Memory allocation failed for summaries\n");
        free(data->rows);
        json_decref(root);
        return 1;
    }
    
    // Initialize summaries
    initialize_summaries(config, data);
    
    // Process each row
    for (int i = 0; i < data->row_count; i++) {
        json_t *row_obj = json_array_get(root, i);
        if (!json_is_object(row_obj)) continue;
        
        DataRow *row = &data->rows[i];
        row->values = malloc(config->column_count * sizeof(char *));
        if (row->values == NULL) {
            fprintf(stderr, "Error: Memory allocation failed for row values\n");
            for (int j = 0; j < i; j++) {
                for (int k = 0; k < config->column_count; k++) {
                    if (data->rows[j].values[k]) free(data->rows[j].values[k]);
                }
                free(data->rows[j].values);
            }
            free(data->rows);
            free(data->summaries);
            json_decref(root);
            return 1;
        }
        
        for (int j = 0; j < config->column_count; j++) {
            const char *key = config->columns[j].key;
            json_t *val = json_object_get(row_obj, key);
            if (json_is_string(val)) {
                row->values[j] = strdup_safe(json_string_value(val));
            } else if (json_is_number(val)) {
                char buffer[32];
                snprintf(buffer, sizeof(buffer), "%g", json_number_value(val));
                row->values[j] = strdup_safe(buffer);
            } else if (json_is_null(val)) {
                row->values[j] = strdup_safe("null");
            } else {
                row->values[j] = strdup_safe("null");
            }
        }
    }
    
    json_decref(root);
    return 0;
}

/*
 * Initialize summaries for each column
 */
void initialize_summaries(TableConfig *config, TableData *data) {
    for (int i = 0; i < config->column_count; i++) {
        SummaryStats *stats = &data->summaries[i];
        memset(stats, 0, sizeof(SummaryStats));
        stats->min_initialized = 0; // Flag to indicate if min has been set
        stats->max_initialized = 0; // Flag to indicate if max has been set
        stats->max_decimal_places = 0; // Initialize max decimal places for float data
    }
}

/*
 * Sort data rows based on sort configuration
 */
void sort_data(TableConfig *config, TableData *data) {
    if (config->sort_count == 0) return;
    
    // TODO: Implement sorting logic
    // For now, just a placeholder to indicate sorting will be done here
}

/*
 * Process data rows, update summaries and calculate widths
 */
void process_data_rows(TableConfig *config, TableData *data) {
    data->max_lines = 1;
    if (data->row_count == 0) return;
    
    for (int i = 0; i < data->row_count; i++) {
        DataRow *row = &data->rows[i];
        int line_count = 1;
        
        for (int j = 0; j < config->column_count; j++) {
            ColumnConfig *col = &config->columns[j];
            const char *value = row->values[j];
            DataType data_type = col->data_type;
            SummaryType summary_type = col->summary;
            
            // Update summaries
            update_summaries(j, value, data_type, summary_type, &data->summaries[j]);
            
            // TODO: Calculate display width and update column widths if not specified
            // TODO: Handle wrapping to determine line count
        }
        
        if (line_count > data->max_lines) {
            data->max_lines = line_count;
        }
    }
    
    // TODO: Update column widths based on summary values if summaries are present
}

/*
 * Helper function to count decimal places in a string representation of a number
 */
static int count_decimal_places(const char *value) {
    const char *decimal_point = strchr(value, '.');
    if (decimal_point == NULL) {
        return 0;
    }
    const char *end = decimal_point + 1;
    while (*end >= '0' && *end <= '9') {
        end++;
    }
    return end - decimal_point - 1;
}

/*
 * Update summary statistics for a column
 */
void update_summaries(int col_idx, const char *value, DataType data_type, SummaryType summary_type, SummaryStats *stats) {
    if (value == NULL || strcmp(value, "null") == 0) {
        return;
    }
    
    // Track maximum decimal places for float data type
    if (data_type == DATA_FLOAT) {
        int decimal_places = count_decimal_places(value);
        if (decimal_places > stats->max_decimal_places) {
            stats->max_decimal_places = decimal_places;
        }
    }
    
    switch (summary_type) {
        case SUMMARY_SUM:
            if (data_type == DATA_KCPU && strstr(value, "m") != NULL) {
                char *num_part = strdup(value);
                num_part[strlen(num_part) - 1] = '\0'; // Remove 'm'
                stats->sum += atof(num_part);
                free(num_part);
            } else if (data_type == DATA_KMEM) {
                // TODO: Handle different memory units
                if (strstr(value, "M") != NULL || strstr(value, "Mi") != NULL) {
                    char *num_part = strdup(value);
                    num_part[strlen(num_part) - (strstr(value, "Mi") ? 2 : 1)] = '\0';
                    stats->sum += atof(num_part);
                    free(num_part);
                } else if (strstr(value, "G") != NULL || strstr(value, "Gi") != NULL) {
                    char *num_part = strdup(value);
                    num_part[strlen(num_part) - (strstr(value, "Gi") ? 2 : 1)] = '\0';
                    stats->sum += atof(num_part) * 1000;
                    free(num_part);
                } else if (strstr(value, "K") != NULL || strstr(value, "Ki") != NULL) {
                    char *num_part = strdup(value);
                    num_part[strlen(num_part) - (strstr(value, "Ki") ? 2 : 1)] = '\0';
                    stats->sum += atof(num_part) / 1000.0;
                    free(num_part);
                }
            } else if (data_type == DATA_INT || data_type == DATA_NUM || data_type == DATA_FLOAT) {
                stats->sum += atof(value);
            }
            break;
        case SUMMARY_MIN:
            if (data_type == DATA_INT || data_type == DATA_NUM || data_type == DATA_FLOAT) {
                double num_val = atof(value);
                if (!stats->min_initialized) {
                    stats->min = num_val;
                    stats->min_initialized = 1;
                } else if (num_val < stats->min) {
                    stats->min = num_val;
                }
            }
            break;
        case SUMMARY_MAX:
            if (data_type == DATA_INT || data_type == DATA_NUM || data_type == DATA_FLOAT) {
                double num_val = atof(value);
                if (!stats->max_initialized) {
                    stats->max = num_val;
                    stats->max_initialized = 1;
                } else if (num_val > stats->max) {
                    stats->max = num_val;
                }
            }
            break;
        case SUMMARY_COUNT:
            stats->count++;
            break;
        case SUMMARY_UNIQUE:
            // Check if value is already in unique_values
            for (int i = 0; i < stats->unique_count; i++) {
                if (strcmp(stats->unique_values[i], value) == 0) {
                    return; // Already exists
                }
            }
            // Add new unique value
            stats->unique_values = realloc(stats->unique_values, (stats->unique_count + 1) * sizeof(char *));
            if (stats->unique_values == NULL) {
                fprintf(stderr, "Error: Memory allocation failed for unique values\n");
                return;
            }
            stats->unique_values[stats->unique_count] = strdup_safe(value);
            stats->unique_count++;
            break;
        case SUMMARY_AVG:
            if (data_type == DATA_INT || data_type == DATA_NUM || data_type == DATA_FLOAT) {
                stats->avg_sum += atof(value);
                stats->avg_count++;
            }
            break;
        default:
            break;
    }
}

/*
 * Free memory allocated for TableData structure
 */
void free_table_data(TableData *data, int column_count) {
    if (data->rows) {
        for (int i = 0; i < data->row_count; i++) {
            DataRow *row = &data->rows[i];
            if (row->values) {
                for (int j = 0; j < column_count; j++) {
                    if (row->values[j]) free(row->values[j]);
                }
                free(row->values);
            }
        }
        free(data->rows);
    }
    
    if (data->summaries) {
        for (int i = 0; i < column_count; i++) {
            SummaryStats *stats = &data->summaries[i];
            if (stats->unique_values) {
                for (int j = 0; j < stats->unique_count; j++) {
                    if (stats->unique_values[j]) free(stats->unique_values[j]);
                }
                free(stats->unique_values);
            }
        }
        free(data->summaries);
    }
    
    // Reset counts
    data->row_count = 0;
    data->max_lines = 0;
}
