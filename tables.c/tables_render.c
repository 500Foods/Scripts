/*
 * tables_render.c - Implementation of table rendering for the tables utility
 * Renders formatted tables to the terminal with ANSI styling.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "tables_render.h"
#include "tables_datatypes.h"

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
 * Calculate display width of text, accounting for ANSI escape codes (which don't take up visible space)
 */
int get_display_width(const char *text) {
    if (text == NULL || strlen(text) == 0) return 0;
    
    int width = 0;
    int in_ansi = 0;
    for (const char *p = text; *p; p++) {
        if (*p == '\033') {
            in_ansi = 1;
        } else if (in_ansi && *p == 'm') {
            in_ansi = 0;
        } else if (!in_ansi) {
            width++;
        }
    }
    return width;
}

/*
 * Wrap text to a specified width, returning an array of lines
 * Handles ANSI escape codes by ignoring them in width calculations
 * Mimics Bash script behavior by building lines word by word
 */
char **wrap_text(const char *text, int width, int *line_count) {
    if (text == NULL || strlen(text) == 0 || width <= 0) {
        *line_count = 1;
        char **lines = malloc(sizeof(char *));
        if (lines == NULL) return NULL;
        lines[0] = strdup("");
        return lines;
    }

    int text_len = strlen(text);
    int lines_capacity = 10;
    char **lines = malloc(lines_capacity * sizeof(char *));
    if (lines == NULL) return NULL;
    *line_count = 0;
    char *current_line = malloc(text_len + 1);
    if (current_line == NULL) {
        free(lines);
        return NULL;
    }
    current_line[0] = '\0';
    int line_pos = 0;
    char *current_word = malloc(text_len + 1);
    if (current_word == NULL) {
        free(current_line);
        free(lines);
        return NULL;
    }
    int word_pos = 0;
    int in_ansi = 0;

    for (int i = 0; i <= text_len; i++) {
        char c = text[i];
        if (c == '\033') {
            in_ansi = 1;
            if (word_pos < text_len) current_word[word_pos++] = c;
        } else if (in_ansi && c == 'm') {
            in_ansi = 0;
            if (word_pos < text_len) current_word[word_pos++] = c;
        } else if (c == ' ' || c == '\0') {
            if (word_pos > 0) {
                current_word[word_pos] = '\0';
                int word_width = get_display_width(current_word);
                int line_width = get_display_width(current_line);
                if (line_width == 0) {
                    strcpy(current_line, current_word);
                    line_pos = strlen(current_word);
                } else if (line_width + word_width + 1 <= width) {
                    strcat(current_line, " ");
                    strcat(current_line, current_word);
                    line_pos = strlen(current_line);
                } else {
                    if (*line_count >= lines_capacity) {
                        lines_capacity *= 2;
                        char **new_lines = realloc(lines, lines_capacity * sizeof(char *));
                        if (new_lines == NULL) {
                            free(current_word);
                            free(current_line);
                            free_wrapped_text(lines, *line_count);
                            return NULL;
                        }
                        lines = new_lines;
                    }
                    lines[*line_count] = strdup(current_line);
                    if (lines[*line_count] == NULL) {
                        free(current_word);
                        free(current_line);
                        free_wrapped_text(lines, *line_count);
                        return NULL;
                    }
                    (*line_count)++;
                    strcpy(current_line, current_word);
                    line_pos = strlen(current_word);
                }
                word_pos = 0;
            }
        } else {
            if (word_pos < text_len) current_word[word_pos++] = c;
        }
    }

    if (line_pos > 0) {
        if (*line_count >= lines_capacity) {
            lines_capacity *= 2;
            char **new_lines = realloc(lines, lines_capacity * sizeof(char *));
            if (new_lines == NULL) {
                free(current_word);
                free(current_line);
                free_wrapped_text(lines, *line_count);
                return NULL;
            }
            lines = new_lines;
        }
        lines[*line_count] = strdup(current_line);
        if (lines[*line_count] == NULL) {
            free(current_word);
            free(current_line);
            free_wrapped_text(lines, *line_count);
            return NULL;
        }
        (*line_count)++;
    }

    free(current_word);
    free(current_line);
    return lines;
}

/*
 * Wrap text based on a delimiter, returning an array of lines
 * Handles ANSI escape codes by ignoring them in width calculations
 * Splits on every delimiter occurrence to match Bash behavior
 */
char **wrap_text_delimiter(const char *text, int width, const char *delimiter, int *line_count) {
    if (text == NULL || strlen(text) == 0 || width <= 0) {
        *line_count = 1;
        char **lines = malloc(sizeof(char *));
        if (lines == NULL) return NULL;
        lines[0] = strdup("");
        return lines;
    }

    int text_len = strlen(text);
    int delimiter_len = strlen(delimiter);
    int lines_capacity = 10;
    char **lines = malloc(lines_capacity * sizeof(char *));
    if (lines == NULL) return NULL;
    *line_count = 0;
    int start = 0;
    char *current_line = malloc(text_len + 1);
    if (current_line == NULL) {
        free(lines);
        return NULL;
    }

    for (int i = 0; i <= text_len; i++) {
        char c = text[i];
        // Check for delimiter or end of text
        if (i + delimiter_len <= text_len && strncmp(text + i, delimiter, delimiter_len) == 0 || c == '\0') {
            if (*line_count >= lines_capacity) {
                lines_capacity *= 2;
                char **new_lines = realloc(lines, lines_capacity * sizeof(char *));
                if (new_lines == NULL) {
                    free(current_line);
                    free_wrapped_text(lines, *line_count);
                    return NULL;
                }
                lines = new_lines;
            }
            // Copy substring from start to i (excluding delimiter)
            int len = i - start;
            if (len > 0) {
                strncpy(current_line, text + start, len);
                current_line[len] = '\0';
                lines[*line_count] = strdup(current_line);
                if (lines[*line_count] == NULL) {
                    free(current_line);
                    free_wrapped_text(lines, *line_count);
                    return NULL;
                }
                (*line_count)++;
            }
            start = i + (c == '\0' ? 0 : delimiter_len);
        }
    }
    free(current_line);
    return lines;
}

/*
 * Free memory allocated for wrapped text lines
 */
void free_wrapped_text(char **lines, int line_count) {
    if (lines) {
        for (int i = 0; i < line_count; i++) {
            if (lines[i]) free(lines[i]);
        }
        free(lines);
    }
}

/*
 * Calculate column widths based on content and configuration
 */
void calculate_column_widths(TableConfig *config, TableData *data) {
    for (int j = 0; j < config->column_count; j++) {
        ColumnConfig *col = &config->columns[j];
        if (col->width_specified) continue; // Width already specified in config
        
        int max_width = 0;
        if (col->header) {
            int header_width = get_display_width(col->header);
            if (header_width > max_width) max_width = header_width;
        }
        
        // Check data rows
        for (int i = 0; i < data->row_count; i++) {
            const char *value = data->rows[i].values[j];
            char *formatted = format_display_value(value, col->null_val, col->zero_val, col->data_type, col->format, col->string_limit, col->wrap_mode, col->wrap_char, col->justify);
            int width = get_display_width(formatted);
            if (width > max_width) max_width = width;
            free(formatted);
        }
        
        // Check summary if present
        if (col->summary != SUMMARY_NONE) {
            SummaryStats *stats = &data->summaries[j];
            char summary_text[256];
            switch (col->summary) {
                case SUMMARY_SUM:
                    if (col->data_type == DATA_FLOAT) {
                        char format[16];
                        snprintf(format, sizeof(format), "%%.%df", stats->max_decimal_places);
                        snprintf(summary_text, sizeof(summary_text), format, stats->sum);
                    } else if (col->data_type == DATA_INT || col->data_type == DATA_NUM) {
                        snprintf(summary_text, sizeof(summary_text), "%.0f", stats->sum);
                    } else {
                        snprintf(summary_text, sizeof(summary_text), "%.2f", stats->sum);
                    }
                    break;
                case SUMMARY_MIN:
                    if (col->data_type == DATA_FLOAT) {
                        char format[16];
                        snprintf(format, sizeof(format), "%%.%df", stats->max_decimal_places);
                        snprintf(summary_text, sizeof(summary_text), format, stats->min);
                    } else if (col->data_type == DATA_INT || col->data_type == DATA_NUM) {
                        snprintf(summary_text, sizeof(summary_text), "%.0f", stats->min);
                    } else {
                        snprintf(summary_text, sizeof(summary_text), "%.2f", stats->min);
                    }
                    break;
                case SUMMARY_MAX:
                    if (col->data_type == DATA_FLOAT) {
                        char format[16];
                        snprintf(format, sizeof(format), "%%.%df", stats->max_decimal_places);
                        snprintf(summary_text, sizeof(summary_text), format, stats->max);
                    } else if (col->data_type == DATA_INT || col->data_type == DATA_NUM) {
                        snprintf(summary_text, sizeof(summary_text), "%.0f", stats->max);
                    } else {
                        snprintf(summary_text, sizeof(summary_text), "%.2f", stats->max);
                    }
                    break;
                case SUMMARY_AVG:
                    if (stats->avg_count > 0) {
                        if (col->data_type == DATA_FLOAT) {
                            char format[16];
                            snprintf(format, sizeof(format), "%%.%df", stats->max_decimal_places);
                            snprintf(summary_text, sizeof(summary_text), format, stats->avg_sum / stats->avg_count);
                        } else if (col->data_type == DATA_INT || col->data_type == DATA_NUM) {
                            snprintf(summary_text, sizeof(summary_text), "%.0f", stats->avg_sum / stats->avg_count);
                        } else {
                            snprintf(summary_text, sizeof(summary_text), "%.2f", stats->avg_sum / stats->avg_count);
                        }
                    } else {
                        snprintf(summary_text, sizeof(summary_text), "N/A");
                    }
                    break;
                case SUMMARY_COUNT:
                    snprintf(summary_text, sizeof(summary_text), "%d", stats->count);
                    break;
                case SUMMARY_UNIQUE:
                    snprintf(summary_text, sizeof(summary_text), "%d", stats->unique_count);
                    break;
                default:
                    summary_text[0] = '\0';
            }
            int summary_width = get_display_width(summary_text);
            if (summary_width > max_width) max_width = summary_width;
        }
        
        col->width = max_width + 2; // Add 1 character padding on each side
    }
}

/*
 * Render the table to the terminal
 */
void render_table(TableConfig *config, TableData *data) {
    // Calculate column widths if not specified
    calculate_column_widths(config, data);
    
    // Calculate total table width
    int total_width = 0;
    int visible_columns = 0;
    for (int j = 0; j < config->column_count; j++) {
        if (config->columns[j].visible) {
            total_width += config->columns[j].width;
            visible_columns++;
        }
    }
    total_width += visible_columns + 1; // Add space for vertical separators
    
    // Render title if present
    if (config->title && strlen(config->title) > 0) {
        int title_width = get_display_width(config->title);
        int padding = 0;
        if (config->title_pos == POSITION_CENTER) {
            padding = (total_width - title_width) / 2;
        } else if (config->title_pos == POSITION_RIGHT) {
            padding = total_width - title_width;
        }
        printf("%s%*s%s%s\n", config->theme.caption_color, padding, "", config->title, config->theme.text_color);
    }
    
    // Render top border
    printf("%s", config->theme.border_color);
    printf("%s", config->theme.tl_corner);
    for (int j = 0; j < config->column_count; j++) {
        if (!config->columns[j].visible) continue;
        for (int w = 0; w < config->columns[j].width; w++) {
            printf("%s", config->theme.h_line);
        }
        if (j < config->column_count - 1) {
            printf("%s", config->theme.t_junct);
        }
    }
    printf("%s%s\n", config->theme.tr_corner, config->theme.text_color);
    
    // Render headers
    printf("%s%s", config->theme.border_color, config->theme.v_line);
    for (int j = 0; j < config->column_count; j++) {
        if (!config->columns[j].visible) continue;
        ColumnConfig *col = &config->columns[j];
        char *header = strdup_safe(col->header ? col->header : "");
        int header_width = get_display_width(header);
        int effective_width = col->width - 2; // Account for 1 space padding on each side
        if (header_width > effective_width && col->wrap_mode == WRAP_CLIP) {
            char *truncated = malloc(col->width + 1);
            if (truncated) {
                int k = 0, display_count = 0;
                int in_ansi = 0;
                const char *start_p = header;
                const char *end_p = header + strlen(header) - 1;
                
                if (col->justify == JUSTIFY_RIGHT) {
                    int target_count = effective_width;
                    for (const char *p = end_p; p >= header && target_count > 0; p--) {
                        if (*p == '\033') in_ansi = 1;
                        else if (in_ansi && *p == 'm') in_ansi = 0;
                        else if (!in_ansi) target_count--;
                        if (target_count <= 0) {
                            start_p = p;
                            break;
                        }
                    }
                    for (const char *p = start_p; *p; p++) {
                        truncated[k++] = *p;
                    }
                } else if (col->justify == JUSTIFY_CENTER) {
                    int total_excess = header_width - effective_width;
                    int left_excess = total_excess / 2;
                    int right_excess = total_excess - left_excess;
                    const char *left_cut = header;
                    const char *right_cut = end_p;
                    int left_count = 0, right_count = 0;
                    
                    for (const char *p = header; *p && left_count < left_excess; p++) {
                        if (*p == '\033') in_ansi = 1;
                        else if (in_ansi && *p == 'm') in_ansi = 0;
                        else if (!in_ansi) left_count++;
                        left_cut = p;
                    }
                    in_ansi = 0;
                    for (const char *p = end_p; p >= header && right_count < right_excess; p--) {
                        if (*p == '\033') in_ansi = 1;
                        else if (in_ansi && *p == 'm') in_ansi = 0;
                        else if (!in_ansi) right_count++;
                        right_cut = p;
                    }
                    // Copy from left_cut + 1 to right_cut - 1 if possible
                    if (left_cut + 1 < right_cut) {
                        for (const char *p = left_cut + 1; p < right_cut && *p; p++) {
                            truncated[k++] = *p;
                        }
                    } else {
                        for (const char *p = left_cut; p <= right_cut && *p; p++) {
                            truncated[k++] = *p;
                        }
                    }
                } else {
                    for (const char *p = header; *p && display_count < effective_width; p++) {
                        if (*p == '\033') in_ansi = 1;
                        else if (in_ansi && *p == 'm') in_ansi = 0;
                        else if (!in_ansi) display_count++;
                        truncated[k++] = *p;
                    }
                }
                truncated[k] = '\0';
                free(header);
                header = truncated;
                header_width = get_display_width(header);
            }
        }
        int total_padding = col->width - header_width;
        int padding_left = 1; // Exactly one space padding on left
        int padding_right = 1; // Exactly one space padding on right
        if (total_padding > 2) { // If more space is available, adjust based on justification
            int remaining_padding = total_padding - 2;
            if (col->justify == JUSTIFY_RIGHT) {
                padding_left += remaining_padding;
            } else if (col->justify == JUSTIFY_CENTER) {
                padding_left += remaining_padding / 2;
                padding_right += remaining_padding - (remaining_padding / 2);
            } else {
                padding_right += remaining_padding;
            }
        }
        printf("%s%*s%s%*s", config->theme.header_color, padding_left, "", header, padding_right, "");
        free(header);
        printf("%s%s", config->theme.border_color, config->theme.v_line);
    }
    printf("%s\n", config->theme.text_color);
    
    // Render header separator
    printf("%s", config->theme.border_color);
    printf("%s", config->theme.l_junct);
    for (int j = 0; j < config->column_count; j++) {
        if (!config->columns[j].visible) continue;
        for (int w = 0; w < config->columns[j].width; w++) {
            printf("%s", config->theme.h_line);
        }
        if (j < config->column_count - 1) {
            printf("%s", config->theme.cross);
        }
    }
    printf("%s%s\n", config->theme.r_junct, config->theme.text_color);
    
    // Render data rows with support for wrapping, truncation, and breaking
    // Find break column if any
    int break_col = -1;
    for (int j = 0; j < config->column_count; j++) {
        if (config->columns[j].break_on_change) {
            break_col = j;
            break;
        }
    }

    // Track the maximum number of lines across all columns for each row
    char ****formatted_values = malloc(data->row_count * sizeof(char ***));
    int **line_counts = malloc(data->row_count * sizeof(int *));
    for (int i = 0; i < data->row_count; i++) {
        formatted_values[i] = malloc(config->column_count * sizeof(char **));
        line_counts[i] = malloc(config->column_count * sizeof(int));
        for (int j = 0; j < config->column_count; j++) {
            formatted_values[i][j] = NULL;
            line_counts[i][j] = 0;
        }
    }

    // Format and wrap text for all cells
    for (int i = 0; i < data->row_count; i++) {
        DataRow *row = &data->rows[i];
        for (int j = 0; j < config->column_count; j++) {
            if (!config->columns[j].visible) continue;
            ColumnConfig *col = &config->columns[j];
            char *raw_value = row->values[j];
            char *formatted = format_display_value(raw_value, col->null_val, col->zero_val, col->data_type, col->format, col->string_limit, col->wrap_mode, col->wrap_char, col->justify);
            if (col->width_specified && col->wrap_mode == WRAP_CLIP) {
                // Truncate if width is specified and wrapping is disabled
                int display_width = get_display_width(formatted);
                int effective_width = col->width - 2; // Account for 1 space padding on each side
                if (display_width > effective_width) {
                    char *truncated = malloc(col->width + 1);
                    if (truncated) {
                        int k = 0, display_count = 0;
                        int in_ansi = 0;
                        const char *start_p = formatted;
                        const char *end_p = formatted + strlen(formatted) - 1;
                        
                        if (col->justify == JUSTIFY_RIGHT) {
                            // For right justification, start from the end and take the last 'effective_width' characters
                            int target_count = effective_width;
                            for (const char *p = end_p; p >= formatted && target_count > 0; p--) {
                                if (*p == '\033') in_ansi = 1;
                                else if (in_ansi && *p == 'm') in_ansi = 0;
                                else if (!in_ansi) target_count--;
                                if (target_count <= 0) {
                                    start_p = p;
                                    break;
                                }
                            }
                            if (start_p < formatted) start_p = formatted;
                            // Copy from start_p to end
                            for (const char *p = start_p; *p; p++) {
                                truncated[k++] = *p;
                            }
                        } else if (col->justify == JUSTIFY_CENTER) {
                            // For center justification, take middle 'effective_width' characters
                            int total_excess = display_width - effective_width;
                            int left_excess = total_excess / 2;
                            int right_excess = total_excess - left_excess;
                            const char *left_cut = formatted;
                            const char *right_cut = end_p;
                            int left_count = 0, right_count = 0;
                            
                            // Cut from left
                            for (const char *p = formatted; *p && left_count < left_excess; p++) {
                                if (*p == '\033') in_ansi = 1;
                                else if (in_ansi && *p == 'm') in_ansi = 0;
                                else if (!in_ansi) left_count++;
                                left_cut = p;
                            }
                            in_ansi = 0; // Reset for right cut
                            // Cut from right
                            for (const char *p = end_p; p >= formatted && right_count < right_excess; p--) {
                                if (*p == '\033') in_ansi = 1;
                                else if (in_ansi && *p == 'm') in_ansi = 0;
                                else if (!in_ansi) right_count++;
                                right_cut = p;
                            }
                            // Copy from left_cut + 1 to right_cut - 1 if possible
                            if (left_cut + 1 < right_cut) {
                                for (const char *p = left_cut + 1; p < right_cut && *p; p++) {
                                    truncated[k++] = *p;
                                }
                            } else {
                                for (const char *p = left_cut; p <= right_cut && *p; p++) {
                                    truncated[k++] = *p;
                                }
                            }
                        } else {
                            // Left justification (default), take first 'effective_width' characters
                            for (const char *p = formatted; *p && display_count < effective_width; p++) {
                                if (*p == '\033') in_ansi = 1;
                                else if (in_ansi && *p == 'm') in_ansi = 0;
                                else if (!in_ansi) display_count++;
                                truncated[k++] = *p;
                            }
                        }
                        truncated[k] = '\0';
                        free(formatted);
                        formatted = truncated;
                    }
                }
                formatted_values[i][j] = malloc(sizeof(char *));
                formatted_values[i][j][0] = formatted;
                line_counts[i][j] = 1;
            } else if (col->width_specified && col->wrap_mode == WRAP_WRAP) {
                // Wrap text if width is specified and wrapping is enabled
                int line_count = 0;
                char **wrapped;
                if (col->wrap_char && strlen(col->wrap_char) > 0) {
                    // Delimiter-based wrapping
                    wrapped = wrap_text_delimiter(formatted, col->width - 2, col->wrap_char, &line_count);
                    if (wrapped) {
                        free(formatted);
                        // Clip each wrapped line if it exceeds the width
                        for (int l = 0; l < line_count; l++) {
                            int display_width = get_display_width(wrapped[l]);
                            int effective_width = col->width - 2;
                            if (display_width > effective_width) {
                                char *truncated = malloc(effective_width + 1);
                                if (truncated) {
                                    int k = 0, display_count = 0;
                                    int in_ansi = 0;
                                    const char *start_p = wrapped[l];
                                    const char *end_p = wrapped[l] + strlen(wrapped[l]) - 1;
                                    
                                    if (col->justify == JUSTIFY_RIGHT) {
                                        int target_count = effective_width;
                                        for (const char *p = end_p; p >= wrapped[l] && target_count > 0; p--) {
                                            if (*p == '\033') in_ansi = 1;
                                            else if (in_ansi && *p == 'm') in_ansi = 0;
                                            else if (!in_ansi) target_count--;
                                            if (target_count <= 0) {
                                                start_p = p + 1;
                                                break;
                                            }
                                        }
                                        if (start_p < wrapped[l]) start_p = wrapped[l];
                                        for (const char *p = start_p; *p; p++) {
                                            truncated[k++] = *p;
                                        }
                                    } else if (col->justify == JUSTIFY_CENTER) {
                                        int total_excess = display_width - effective_width;
                                        int left_excess = total_excess / 2;
                                        int right_excess = total_excess - left_excess;
                                        const char *left_cut = wrapped[l];
                                        const char *right_cut = end_p;
                                        int left_count = 0, right_count = 0;
                                        
                                        for (const char *p = wrapped[l]; *p && left_count < left_excess; p++) {
                                            if (*p == '\033') in_ansi = 1;
                                            else if (in_ansi && *p == 'm') in_ansi = 0;
                                            else if (!in_ansi) left_count++;
                                            left_cut = p;
                                        }
                                        in_ansi = 0;
                                        for (const char *p = end_p; p >= wrapped[l] && right_count < right_excess; p--) {
                                            if (*p == '\033') in_ansi = 1;
                                            else if (in_ansi && *p == 'm') in_ansi = 0;
                                            else if (!in_ansi) right_count++;
                                            right_cut = p;
                                        }
                                        // Adjust to match Bash behavior by fine-tuning centering
                                        if (left_cut < right_cut) {
                                            for (const char *p = left_cut + 1; p <= right_cut && *p; p++) {
                                                if (display_count < effective_width) {
                                                    truncated[k++] = *p;
                                                    if (!in_ansi && *p != '\033') display_count++;
                                                }
                                            }
                                        } else {
                                            for (const char *p = left_cut; p <= right_cut && *p; p++) {
                                                truncated[k++] = *p;
                                            }
                                        }
                                    } else {
                                        for (const char *p = wrapped[l]; *p && display_count < effective_width; p++) {
                                            if (*p == '\033') in_ansi = 1;
                                            else if (in_ansi && *p == 'm') in_ansi = 0;
                                            else if (!in_ansi) display_count++;
                                            truncated[k++] = *p;
                                        }
                                    }
                                    truncated[k] = '\0';
                                    free(wrapped[l]);
                                    wrapped[l] = truncated;
                                }
                            }
                        }
                        formatted_values[i][j] = wrapped;
                        line_counts[i][j] = line_count;
                    } else {
                        formatted_values[i][j] = malloc(sizeof(char *));
                        formatted_values[i][j][0] = formatted;
                        line_counts[i][j] = 1;
                    }
                } else {
                    // Standard word wrapping
                    wrapped = wrap_text(formatted, col->width - 2, &line_count);
                    if (wrapped) {
                        free(formatted);
                        formatted_values[i][j] = wrapped;
                        line_counts[i][j] = line_count;
                    } else {
                        formatted_values[i][j] = malloc(sizeof(char *));
                        formatted_values[i][j][0] = formatted;
                        line_counts[i][j] = 1;
                    }
                }
            } else {
                // No wrapping or truncation needed
                formatted_values[i][j] = malloc(sizeof(char *));
                formatted_values[i][j][0] = formatted;
                line_counts[i][j] = 1;
            }
        }
    }

    // Render rows with multi-line support and breaking
    char *prev_break_value = NULL;
    for (int i = 0; i < data->row_count; i++) {
        // Check for break
        if (break_col >= 0 && i > 0) {
            char *current_break_value = data->rows[i].values[break_col];
            if (prev_break_value && current_break_value && strcmp(prev_break_value, current_break_value) != 0) {
                // Render break separator
                printf("%s", config->theme.border_color);
                printf("%s", config->theme.l_junct);
                for (int j = 0; j < config->column_count; j++) {
                    if (!config->columns[j].visible) continue;
                    for (int w = 0; w < config->columns[j].width; w++) {
                        printf("%s", config->theme.h_line);
                    }
                    if (j < config->column_count - 1) {
                        printf("%s", config->theme.cross);
                    }
                }
                printf("%s%s\n", config->theme.r_junct, config->theme.text_color);
            }
            prev_break_value = current_break_value;
        } else if (i == 0 && break_col >= 0) {
            prev_break_value = data->rows[i].values[break_col];
        }

        // Determine max lines for this row
        int max_lines = 1;
        for (int j = 0; j < config->column_count; j++) {
            if (!config->columns[j].visible) continue;
            if (line_counts[i][j] > max_lines) max_lines = line_counts[i][j];
        }

        // Render each line of the row
        for (int line = 0; line < max_lines; line++) {
            printf("%s%s", config->theme.border_color, config->theme.v_line);
            for (int j = 0; j < config->column_count; j++) {
                if (!config->columns[j].visible) continue;
                ColumnConfig *col = &config->columns[j];
                char *text = (line < line_counts[i][j]) ? formatted_values[i][j][line] : "";
                int value_width = get_display_width(text);
                int total_padding = col->width - value_width;
                int padding_left = 1; // Exactly one space padding on left
                int padding_right = 1; // Exactly one space padding on right
                if (total_padding > 2) { // Adjust based on justification
                    int remaining_padding = total_padding - 2;
                    if (col->justify == JUSTIFY_RIGHT) {
                        padding_left += remaining_padding;
                    } else if (col->justify == JUSTIFY_CENTER) {
                        padding_left += remaining_padding / 2;
                        padding_right += remaining_padding - (remaining_padding / 2);
                    } else {
                        padding_right += remaining_padding;
                    }
                }
                printf("%s%*s%s%*s", config->theme.text_color, padding_left, "", text, padding_right, "");
                printf("%s%s", config->theme.border_color, config->theme.v_line);
            }
            printf("%s\n", config->theme.text_color);
        }
    }

    // Clean up formatted values
    for (int i = 0; i < data->row_count; i++) {
        for (int j = 0; j < config->column_count; j++) {
            if (formatted_values[i][j]) {
                free_wrapped_text(formatted_values[i][j], line_counts[i][j]);
            }
        }
        free(formatted_values[i]);
        free(line_counts[i]);
    }
    free(formatted_values);
    free(line_counts);
    
    // Render summaries if any
    int has_summaries = 0;
    for (int j = 0; j < config->column_count; j++) {
        if (config->columns[j].summary != SUMMARY_NONE) {
            has_summaries = 1;
            break;
        }
    }
    if (has_summaries) {
        // Render summary separator
        printf("%s", config->theme.border_color);
        printf("%s", config->theme.l_junct);
        for (int j = 0; j < config->column_count; j++) {
            if (!config->columns[j].visible) continue;
            for (int w = 0; w < config->columns[j].width; w++) {
                printf("%s", config->theme.h_line);
            }
            if (j < config->column_count - 1) {
                printf("%s", config->theme.cross);
            }
        }
        printf("%s%s\n", config->theme.r_junct, config->theme.text_color);
        
        // Render summary row
        printf("%s%s", config->theme.border_color, config->theme.v_line);
        for (int j = 0; j < config->column_count; j++) {
            if (!config->columns[j].visible) continue;
            ColumnConfig *col = &config->columns[j];
            SummaryStats *stats = &data->summaries[j];
            char summary_text[256] = {0};
            switch (col->summary) {
                case SUMMARY_SUM:
                    if (col->data_type == DATA_KCPU) {
                        snprintf(summary_text, sizeof(summary_text), "%.0f", stats->sum);
                        char *formatted = format_with_commas(summary_text);
                        snprintf(summary_text, sizeof(summary_text), "%sm", formatted);
                        free(formatted);
                    } else if (col->data_type == DATA_KMEM) {
                        snprintf(summary_text, sizeof(summary_text), "%.0f", stats->sum);
                        char *formatted = format_with_commas(summary_text);
                        snprintf(summary_text, sizeof(summary_text), "%sM", formatted);
                        free(formatted);
                    } else if (col->data_type == DATA_FLOAT) {
                        char format[16];
                        snprintf(format, sizeof(format), "%%.%df", stats->max_decimal_places);
                        snprintf(summary_text, sizeof(summary_text), format, stats->sum);
                    } else if (col->data_type == DATA_INT || col->data_type == DATA_NUM) {
                        snprintf(summary_text, sizeof(summary_text), "%.0f", stats->sum);
                    } else {
                        snprintf(summary_text, sizeof(summary_text), "%.2f", stats->sum);
                    }
                    break;
                case SUMMARY_MIN:
                    if (col->data_type == DATA_FLOAT) {
                        char format[16];
                        snprintf(format, sizeof(format), "%%.%df", stats->max_decimal_places);
                        snprintf(summary_text, sizeof(summary_text), format, stats->min);
                    } else if (col->data_type == DATA_INT || col->data_type == DATA_NUM) {
                        snprintf(summary_text, sizeof(summary_text), "%.0f", stats->min);
                    } else {
                        snprintf(summary_text, sizeof(summary_text), "%.2f", stats->min);
                    }
                    break;
                case SUMMARY_MAX:
                    if (col->data_type == DATA_FLOAT) {
                        char format[16];
                        snprintf(format, sizeof(format), "%%.%df", stats->max_decimal_places);
                        snprintf(summary_text, sizeof(summary_text), format, stats->max);
                    } else if (col->data_type == DATA_INT || col->data_type == DATA_NUM) {
                        snprintf(summary_text, sizeof(summary_text), "%.0f", stats->max);
                    } else {
                        snprintf(summary_text, sizeof(summary_text), "%.2f", stats->max);
                    }
                    break;
                case SUMMARY_AVG:
                    if (stats->avg_count > 0) {
                        if (col->data_type == DATA_FLOAT) {
                            char format[16];
                            snprintf(format, sizeof(format), "%%.%df", stats->max_decimal_places);
                            snprintf(summary_text, sizeof(summary_text), format, stats->avg_sum / stats->avg_count);
                        } else if (col->data_type == DATA_INT || col->data_type == DATA_NUM) {
                            snprintf(summary_text, sizeof(summary_text), "%.0f", stats->avg_sum / stats->avg_count);
                        } else {
                            snprintf(summary_text, sizeof(summary_text), "%.2f", stats->avg_sum / stats->avg_count);
                        }
                    } else {
                        snprintf(summary_text, sizeof(summary_text), "N/A");
                    }
                    break;
                case SUMMARY_COUNT:
                    snprintf(summary_text, sizeof(summary_text), "%d", stats->count);
                    break;
                case SUMMARY_UNIQUE:
                    snprintf(summary_text, sizeof(summary_text), "%d", stats->unique_count);
                    break;
                default:
                    summary_text[0] = '\0';
            }
            char *summary_display = strdup_safe(summary_text);
            int summary_width = get_display_width(summary_display);
            int effective_width = col->width - 2; // Account for 1 space padding on each side
            if (summary_width > effective_width && col->wrap_mode == WRAP_CLIP) {
                char *truncated = malloc(col->width + 1);
                if (truncated) {
                    int k = 0, display_count = 0;
                    int in_ansi = 0;
                    const char *start_p = summary_display;
                    const char *end_p = summary_display + strlen(summary_display) - 1;
                    
                if (col->justify == JUSTIFY_RIGHT) {
                    int target_count = effective_width;
                    for (const char *p = end_p; p >= summary_display && target_count > 0; p--) {
                        if (*p == '\033') in_ansi = 1;
                        else if (in_ansi && *p == 'm') in_ansi = 0;
                        else if (!in_ansi) target_count--;
                        if (target_count <= 0) {
                            start_p = p;
                            break;
                        }
                    }
                    if (start_p < summary_display) start_p = summary_display;
                    for (const char *p = start_p; *p; p++) {
                        truncated[k++] = *p;
                    }
                } else if (col->justify == JUSTIFY_CENTER) {
                    int total_excess = summary_width - effective_width;
                    int left_excess = total_excess / 2;
                    int right_excess = total_excess - left_excess;
                    const char *left_cut = summary_display;
                    const char *right_cut = end_p;
                    int left_count = 0, right_count = 0;
                    
                    for (const char *p = summary_display; *p && left_count < left_excess; p++) {
                        if (*p == '\033') in_ansi = 1;
                        else if (in_ansi && *p == 'm') in_ansi = 0;
                        else if (!in_ansi) left_count++;
                        left_cut = p;
                    }
                    in_ansi = 0;
                    for (const char *p = end_p; p >= summary_display && right_count < right_excess; p--) {
                        if (*p == '\033') in_ansi = 1;
                        else if (in_ansi && *p == 'm') in_ansi = 0;
                        else if (!in_ansi) right_count++;
                        right_cut = p;
                    }
                    // Copy from left_cut + 1 to right_cut - 1 if possible
                    if (left_cut + 1 < right_cut) {
                        for (const char *p = left_cut + 1; p < right_cut && *p; p++) {
                            truncated[k++] = *p;
                        }
                    } else {
                        for (const char *p = left_cut; p <= right_cut && *p; p++) {
                            truncated[k++] = *p;
                        }
                    }
                } else {
                    for (const char *p = summary_display; *p && display_count < effective_width; p++) {
                        if (*p == '\033') in_ansi = 1;
                        else if (in_ansi && *p == 'm') in_ansi = 0;
                        else if (!in_ansi) display_count++;
                        truncated[k++] = *p;
                    }
                }
                truncated[k] = '\0';
                free(summary_display);
                summary_display = truncated;
                summary_width = get_display_width(summary_display);
            }
            }
            int total_padding = col->width - summary_width;
            int padding_left = 1; // Exactly one space padding on left
            int padding_right = 1; // Exactly one space padding on right
            if (total_padding > 2) { // If more space is available, adjust based on justification
                int remaining_padding = total_padding - 2;
                if (col->justify == JUSTIFY_RIGHT) {
                    padding_left += remaining_padding;
                } else if (col->justify == JUSTIFY_CENTER) {
                    padding_left += remaining_padding / 2;
                    padding_right += remaining_padding - (remaining_padding / 2);
                } else {
                    padding_right += remaining_padding;
                }
            }
            printf("%s%*s%s%*s", config->theme.summary_color, padding_left, "", summary_display, padding_right, "");
            free(summary_display);
            printf("%s%s", config->theme.border_color, config->theme.v_line);
        }
        printf("%s\n", config->theme.text_color);
    }
    
    // Render bottom border
    printf("%s", config->theme.border_color);
    printf("%s", config->theme.bl_corner);
    for (int j = 0; j < config->column_count; j++) {
        if (!config->columns[j].visible) continue;
        for (int w = 0; w < config->columns[j].width; w++) {
            printf("%s", config->theme.h_line);
        }
        if (j < config->column_count - 1) {
            printf("%s", config->theme.b_junct);
        }
    }
    printf("%s%s\n", config->theme.br_corner, config->theme.text_color);
    
    // Render footer if present
    if (config->footer && strlen(config->footer) > 0) {
        int footer_width = get_display_width(config->footer);
        int padding = 0;
        if (config->footer_pos == POSITION_CENTER) {
            padding = (total_width - footer_width) / 2;
        } else if (config->footer_pos == POSITION_RIGHT) {
            padding = total_width - footer_width;
        }
        printf("%s%*s%s%s\n", config->theme.footer_color, padding, "", config->footer, config->theme.text_color);
    }
}
