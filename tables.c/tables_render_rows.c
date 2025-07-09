/*
 * tables_render_rows.c - Functions for rendering table data rows with multi-line support and breaking
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tables_render_rows.h"
#include "tables_render_utils.h"

/*
 * Render the data rows of the table with support for wrapping, truncation, and breaking
 */
void render_rows(TableConfig *config, TableData *data) {
    extern int debug_mode;
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
    if (formatted_values == NULL) {
        fprintf(stderr, "Error: Memory allocation failed for formatted_values\n");
        return;
    }
    int **line_counts = malloc(data->row_count * sizeof(int *));
    if (line_counts == NULL) {
        fprintf(stderr, "Error: Memory allocation failed for line_counts\n");
        free(formatted_values);
        return;
    }
    for (int i = 0; i < data->row_count; i++) {
        formatted_values[i] = malloc(config->column_count * sizeof(char **));
        if (formatted_values[i] == NULL) {
            fprintf(stderr, "Error: Memory allocation failed for formatted_values[%d]\n", i);
            for (int k = 0; k < i; k++) {
                free(formatted_values[k]);
            }
            free(formatted_values);
            free(line_counts);
            return;
        }
        line_counts[i] = malloc(config->column_count * sizeof(int));
        if (line_counts[i] == NULL) {
            fprintf(stderr, "Error: Memory allocation failed for line_counts[%d]\n", i);
            free(formatted_values[i]);
            for (int k = 0; k < i; k++) {
                free(formatted_values[k]);
                free(line_counts[k]);
            }
            free(formatted_values);
            free(line_counts);
            return;
        }
        for (int j = 0; j < config->column_count; j++) {
            formatted_values[i][j] = NULL;
            line_counts[i][j] = 0;
        }
    }
    if (debug_mode) {
        fprintf(stderr, "Debug: Allocated memory for formatted_values and line_counts for %d rows and %d columns\n", data->row_count, config->column_count);
    }

    // Format and wrap text for all cells
    for (int i = 0; i < data->row_count; i++) {
        DataRow *row = &data->rows[i];
        for (int j = 0; j < config->column_count; j++) {
            if (!config->columns[j].visible) continue;
            ColumnConfig *col = &config->columns[j];
            char *raw_value = row->values[j];
            char *formatted = format_display_value_with_precision(raw_value, col->null_val, col->zero_val, col->data_type, col->format, col->string_limit, col->wrap_mode, col->wrap_char, col->justify, data->summaries[j].max_decimal_places);
            if (col->width_specified && col->wrap_mode == WRAP_CLIP) {
                // Truncate if width is specified and wrapping is disabled
                int display_width = get_display_width(formatted);
                int effective_width = col->width - 2; // Account for padding on both sides (1 left + 1 right)
                if (display_width > effective_width) {
                    char *truncated = malloc(col->width + 1);
                    if (truncated) {
                        int k = 0, display_count = 0;
                        int in_ansi = 0;
                        const char *end_p = formatted + strlen(formatted) - 1;
                        
                        if (col->justify == JUSTIFY_RIGHT) {
                            // For right justification, start from the end and take the last 'effective_width' characters
                            int char_count = 0;
                            const char *start_pos = formatted;
                            
                            // Count total display characters first
                            int total_chars = get_display_width(formatted);
                            int chars_to_skip = total_chars - effective_width;
                            
                            // Skip the first chars_to_skip display characters
                            for (const char *p = formatted; *p && char_count < chars_to_skip; p++) {
                                if (*p == '\033') {
                                    in_ansi = 1;
                                    start_pos = p;
                                } else if (in_ansi && *p == 'm') {
                                    in_ansi = 0;
                                    start_pos = p + 1;
                                } else if (in_ansi) {
                                    start_pos = p;
                                } else {
                                    char_count++;
                                    start_pos = p + 1;
                                }
                            }
                            
                            // Copy from start_pos to end
                            for (const char *p = start_pos; *p; p++) {
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
                            int effective_width = (col->justify == JUSTIFY_RIGHT) ? col->width - 1 : col->width - 2;
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
                                        // Left justification (default), take first 'effective_width' characters
                                        // Use same logic as main clipping section (lines 152-158)
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
                int padding_left = 1;  // Minimum 1 space padding on left
                int padding_right = 1; // Minimum 1 space padding on right
                int remaining_padding = total_padding - 2; // Account for minimum padding
                if (remaining_padding > 0) {
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
    if (debug_mode) {
        fprintf(stderr, "Debug: Freed memory for formatted_values and line_counts\n");
    }
}
