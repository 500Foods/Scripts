/*
 * tables_config.c - Implementation of configuration parsing for the tables utility
 * Parses layout JSON files and manages configuration structures.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <jansson.h>
#include "tables_config.h"

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
 * Helper function to parse justification string to enum
 */
static Justification parse_justification(const char *str) {
    if (str == NULL) return JUSTIFY_LEFT;
    if (strcasecmp(str, "right") == 0) return JUSTIFY_RIGHT;
    if (strcasecmp(str, "center") == 0) return JUSTIFY_CENTER;
    return JUSTIFY_LEFT;
}

/*
 * Helper function to parse data type string to enum
 */
static DataType parse_data_type(const char *str) {
    if (str == NULL) return DATA_TEXT;
    if (strcasecmp(str, "int") == 0) return DATA_INT;
    if (strcasecmp(str, "num") == 0) return DATA_NUM;
    if (strcasecmp(str, "float") == 0) return DATA_FLOAT;
    if (strcasecmp(str, "kcpu") == 0) return DATA_KCPU;
    if (strcasecmp(str, "kmem") == 0) return DATA_KMEM;
    return DATA_TEXT;
}

/*
 * Helper function to parse value display string to enum
 */
static ValueDisplay parse_value_display(const char *str) {
    if (str == NULL) return VALUE_BLANK;
    if (strcasecmp(str, "0") == 0) return VALUE_ZERO;
    if (strcasecmp(str, "missing") == 0) return VALUE_MISSING;
    return VALUE_BLANK;
}

/*
 * Helper function to parse summary type string to enum
 */
static SummaryType parse_summary_type(const char *str) {
    if (str == NULL) return SUMMARY_NONE;
    if (strcasecmp(str, "sum") == 0) return SUMMARY_SUM;
    if (strcasecmp(str, "min") == 0) return SUMMARY_MIN;
    if (strcasecmp(str, "max") == 0) return SUMMARY_MAX;
    if (strcasecmp(str, "avg") == 0) return SUMMARY_AVG;
    if (strcasecmp(str, "count") == 0) return SUMMARY_COUNT;
    if (strcasecmp(str, "unique") == 0) return SUMMARY_UNIQUE;
    return SUMMARY_NONE;
}

/*
 * Helper function to parse wrap mode string to enum
 */
static WrapMode parse_wrap_mode(const char *str) {
    if (str == NULL) return WRAP_CLIP;
    if (strcasecmp(str, "wrap") == 0) return WRAP_WRAP;
    return WRAP_CLIP;
}

/*
 * Helper function to parse position string to enum
 */
static Position parse_position(const char *str) {
    if (str == NULL) return POSITION_NONE;
    if (strcasecmp(str, "left") == 0) return POSITION_LEFT;
    if (strcasecmp(str, "right") == 0) return POSITION_RIGHT;
    if (strcasecmp(str, "center") == 0) return POSITION_CENTER;
    if (strcasecmp(str, "full") == 0) return POSITION_FULL;
    return POSITION_NONE;
}

/*
 * Validate input files exist and are non-empty
 */
int validate_input_files(const char *layout_file, const char *data_file) {
    FILE *fp;
    
    fp = fopen(layout_file, "r");
    if (fp == NULL) {
        fprintf(stderr, "Error: Cannot open layout file %s\n", layout_file);
        return 1;
    }
    fclose(fp);
    
    fp = fopen(data_file, "r");
    if (fp == NULL) {
        fprintf(stderr, "Error: Cannot open data file %s\n", data_file);
        return 1;
    }
    fclose(fp);
    
    return 0;
}

/*
 * Parse layout JSON file into TableConfig structure
 */
int parse_layout_file(const char *filename, TableConfig *config) {
    json_t *root;
    json_error_t error;
    FILE *fp;
    char *buffer = NULL;
    size_t buffer_size = 0;
    size_t total_read = 0;
    size_t chunk_size = 1024;
    
    fp = fopen(filename, "r");
    if (fp == NULL) {
        fprintf(stderr, "Error: Cannot open layout file %s\n", filename);
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
                fprintf(stderr, "Error: Reading layout file %s\n", filename);
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
        fprintf(stderr, "Error: JSON parsing failed for %s: %s\n", filename, error.text);
        return 1;
    }
    
    // Initialize config structure
    memset(config, 0, sizeof(TableConfig));
    
    // Parse theme name
    json_t *theme_val = json_object_get(root, "theme");
    config->theme_name = strdup_safe(json_string_value(theme_val) ? json_string_value(theme_val) : "Red");
    
    // Parse title and position
    json_t *title_val = json_object_get(root, "title");
    config->title = strdup_safe(json_string_value(title_val));
    json_t *title_pos_val = json_object_get(root, "title_position");
    config->title_pos = parse_position(json_string_value(title_pos_val));
    
    // Parse footer and position
    json_t *footer_val = json_object_get(root, "footer");
    config->footer = strdup_safe(json_string_value(footer_val));
    json_t *footer_pos_val = json_object_get(root, "footer_position");
    config->footer_pos = parse_position(json_string_value(footer_pos_val));
    
    // Parse columns array
    json_t *columns_array = json_object_get(root, "columns");
    if (!json_is_array(columns_array) || json_array_size(columns_array) == 0) {
        fprintf(stderr, "Error: No columns defined in layout JSON\n");
        json_decref(root);
        free_table_config(config);
        return 1;
    }
    
    config->column_count = json_array_size(columns_array);
    if (config->column_count > MAX_COLUMNS) {
        fprintf(stderr, "Warning: Too many columns, truncating to %d\n", MAX_COLUMNS);
        config->column_count = MAX_COLUMNS;
    }
    
    config->columns = malloc(config->column_count * sizeof(ColumnConfig));
    if (config->columns == NULL) {
        fprintf(stderr, "Error: Memory allocation failed for columns\n");
        json_decref(root);
        free_table_config(config);
        return 1;
    }
    
    for (int i = 0; i < config->column_count; i++) {
        json_t *col_obj = json_array_get(columns_array, i);
        if (!json_is_object(col_obj)) continue;
        
        ColumnConfig *col = &config->columns[i];
        memset(col, 0, sizeof(ColumnConfig));
        
        json_t *header_val = json_object_get(col_obj, "header");
        col->header = strdup_safe(json_string_value(header_val));
        if (col->header == NULL || strlen(col->header) == 0) {
            fprintf(stderr, "Error: Column %d has no header\n", i);
            json_decref(root);
            free_table_config(config);
            return 1;
        }
        
        json_t *key_val = json_object_get(col_obj, "key");
        const char *key_str = json_string_value(key_val);
        if (key_str == NULL || strlen(key_str) == 0) {
            // Derive key from header (lowercase, replace non-alphanumeric with underscore)
            char *derived_key = strdup(col->header);
            for (char *p = derived_key; *p; p++) {
                if (!isalnum(*p)) *p = '_';
                else *p = tolower(*p);
            }
            col->key = derived_key;
        } else {
            col->key = strdup_safe(key_str);
        }
        
        json_t *justify_val = json_object_get(col_obj, "justification");
        col->justify = parse_justification(json_string_value(justify_val));
        
        json_t *datatype_val = json_object_get(col_obj, "datatype");
        col->data_type = parse_data_type(json_string_value(datatype_val));
        
        json_t *null_val = json_object_get(col_obj, "null_value");
        col->null_val = parse_value_display(json_string_value(null_val));
        
        json_t *zero_val = json_object_get(col_obj, "zero_value");
        col->zero_val = parse_value_display(json_string_value(zero_val));
        
        json_t *format_val = json_object_get(col_obj, "format");
        col->format = strdup_safe(json_string_value(format_val));
        
        json_t *summary_val = json_object_get(col_obj, "summary");
        col->summary = parse_summary_type(json_string_value(summary_val));
        
        json_t *break_val = json_object_get(col_obj, "break");
        col->break_on_change = json_is_true(break_val);
        
        json_t *string_limit_val = json_object_get(col_obj, "string_limit");
        col->string_limit = json_is_number(string_limit_val) ? json_integer_value(string_limit_val) : 0;
        
        json_t *wrap_mode_val = json_object_get(col_obj, "wrap_mode");
        col->wrap_mode = parse_wrap_mode(json_string_value(wrap_mode_val));
        
        json_t *wrap_char_val = json_object_get(col_obj, "wrap_char");
        col->wrap_char = strdup_safe(json_string_value(wrap_char_val));
        
        json_t *padding_val = json_object_get(col_obj, "padding");
        col->padding = json_is_number(padding_val) ? json_integer_value(padding_val) : DEFAULT_PADDING;
        
        json_t *width_val = json_object_get(col_obj, "width");
        col->width = json_is_number(width_val) ? json_integer_value(width_val) : 0;
        col->width_specified = (col->width > 0);
        
        json_t *visible_val = json_object_get(col_obj, "visible");
        col->visible = json_is_boolean(visible_val) ? json_is_true(visible_val) : 1;
    }
    
    // Parse sort array
    json_t *sort_array = json_object_get(root, "sort");
    if (json_is_array(sort_array)) {
        config->sort_count = json_array_size(sort_array);
        config->sorts = malloc(config->sort_count * sizeof(SortConfig));
        if (config->sorts == NULL && config->sort_count > 0) {
            fprintf(stderr, "Error: Memory allocation failed for sort config\n");
            json_decref(root);
            free_table_config(config);
            return 1;
        }
        
        for (int i = 0; i < config->sort_count; i++) {
            json_t *sort_obj = json_array_get(sort_array, i);
            if (!json_is_object(sort_obj)) continue;
            
            SortConfig *sort = &config->sorts[i];
            memset(sort, 0, sizeof(SortConfig));
            
            json_t *key_val = json_object_get(sort_obj, "key");
            sort->key = strdup_safe(json_string_value(key_val));
            
            json_t *dir_val = json_object_get(sort_obj, "direction");
            const char *dir_str = json_string_value(dir_val);
            sort->direction = (dir_str && strcasecmp(dir_str, "desc") == 0) ? 1 : 0;
            
            json_t *priority_val = json_object_get(sort_obj, "priority");
            sort->priority = json_is_number(priority_val) ? json_integer_value(priority_val) : 0;
        }
    } else {
        config->sort_count = 0;
        config->sorts = NULL;
    }
    
    json_decref(root);
    return 0;
}

/*
 * Free memory allocated for TableConfig structure
 */
void free_table_config(TableConfig *config) {
    if (config->theme_name) free(config->theme_name);
    if (config->title) free(config->title);
    if (config->footer) free(config->footer);
    
    if (config->columns) {
        for (int i = 0; i < config->column_count; i++) {
            ColumnConfig *col = &config->columns[i];
            if (col->header) free(col->header);
            if (col->key) free(col->key);
            if (col->format) free(col->format);
            if (col->wrap_char) free(col->wrap_char);
        }
        free(config->columns);
    }
    
    if (config->sorts) {
        for (int i = 0; i < config->sort_count; i++) {
            SortConfig *sort = &config->sorts[i];
            if (sort->key) free(sort->key);
        }
        free(config->sorts);
    }
    
    // Reset counts
    config->column_count = 0;
    config->sort_count = 0;
}
