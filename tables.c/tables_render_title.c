/*
 * tables_render_title.c - Functions for rendering the title box of a table
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tables_render_title.h"
#include "tables_render_utils.h"

/*
 * Render the title box with proper borders and positioning
 */
void render_title(TableConfig *config, int total_width) {
    int title_present = (config->title && strlen(config->title) > 0);
    if (!title_present) return;

    char *evaluated_title = evaluate_dynamic_string(config->title);
    if (evaluated_title == NULL) {
        fprintf(stderr, "Error: Failed to evaluate dynamic title string\n");
        evaluated_title = strdup(config->title ? config->title : "");
        if (evaluated_title == NULL) {
            fprintf(stderr, "Error: Memory allocation failed for title string\n");
            return;
        }
    }

    char *processed_title = replace_color_placeholders(evaluated_title);
    if (processed_title == NULL) {
        fprintf(stderr, "Error: Failed to process color placeholders in title\n");
        processed_title = strdup(evaluated_title);
        if (processed_title == NULL) {
            fprintf(stderr, "Error: Memory allocation failed for processed title string\n");
            free(evaluated_title);
            return;
        }
    }
    free(evaluated_title);

    int title_width = get_display_width(processed_title);
    int box_width = title_width + 4; // Add padding for box borders and internal padding
    int title_padding = 0;
    int title_right_edge = 0;

    // Limit box_width to total_width only if title position is specified (left, center, right, full)
    if (box_width > total_width && config->title_pos != POSITION_NONE) {
        box_width = total_width;
    }

    if (config->title_pos == POSITION_CENTER) {
        title_padding = (total_width - box_width) / 2;
        title_right_edge = title_padding + box_width - 1;
    } else if (config->title_pos == POSITION_RIGHT) {
        title_padding = total_width - box_width;
        title_right_edge = total_width - 1;
    } else if (config->title_pos == POSITION_FULL) {
        box_width = total_width;
        title_padding = 0;
        title_right_edge = total_width - 1;
    } else { // POSITION_LEFT or default
        title_padding = 0;
        title_right_edge = box_width - 1;
    }
    // Use title_right_edge to avoid unused variable warning
    (void)title_right_edge; // This line ensures the variable is used

    // Top border of title box - always use rounded corners
    printf("%s%*s%s", config->theme.border_color, title_padding, "", config->theme.tl_corner);
    for (int i = 0; i < box_width - 2; i++) {
        printf("%s", config->theme.h_line);
    }
    printf("%s%s\n", config->theme.tr_corner, config->theme.text_color);

    // Title line with side borders, clip title if it exceeds box width
    char *display_title = processed_title;
    int max_title_width = box_width - 4; // Account for borders and padding
    if (title_width > max_title_width) {
        display_title = malloc(max_title_width + 1);
        if (display_title) {
            if (config->title_pos == POSITION_CENTER) {
                // For center alignment, clip from both sides
                int excess = title_width - max_title_width;
                int start = excess / 2;
                strncpy(display_title, processed_title + start, max_title_width);
                display_title[max_title_width] = '\0';
            } else if (config->title_pos == POSITION_RIGHT) {
                // For right alignment, clip from the left
                int start = title_width - max_title_width;
                strncpy(display_title, processed_title + start, max_title_width);
                display_title[max_title_width] = '\0';
            } else {
                // Default or left alignment clip from the right
                strncpy(display_title, processed_title, max_title_width);
                display_title[max_title_width] = '\0';
            }
        }
    }
    // Use vertical lines for title borders; connectors are handled in border rendering
    const char *left_border = config->theme.v_line;
    const char *right_border = config->theme.v_line;
    printf("%s%*s%s%s %s %s%s\n", config->theme.border_color, title_padding, "", left_border, config->theme.caption_color, display_title, config->theme.border_color, right_border);
    if (display_title != processed_title) {
        free(display_title);
    }
    free(processed_title);
}

/*
 * Render the top border of the table, integrating with title's bottom border if present
 */
void render_top_border_with_title(TableConfig *config, int total_width, int title_present, int title_padding, int title_right_edge, int box_width) {
    // Note: title_right_edge is used in this function
    printf("%s", config->theme.border_color);
    int current_pos = 0;

    // Calculate column positions for junctions
    int *column_positions = malloc((config->column_count - 1) * sizeof(int));
    int col_pos_count = 0;
    int col_width_sum = 0;
    for (int j = 0; j < config->column_count - 1; j++) {
        if (!config->columns[j].visible) continue;
        col_width_sum += config->columns[j].width;
        int next_visible = 0;
        for (int k = j + 1; k < config->column_count; k++) {
            if (config->columns[k].visible) {
                next_visible = 1;
                break;
            }
        }
        if (next_visible) {
            column_positions[col_pos_count++] = col_width_sum;
            col_width_sum++; // Account for vertical line
        }
    }

    if (title_present) {
        // Start from the left-most position of the table
        current_pos = 0;
        // Extend beyond table width if title position is none
        int max_width = total_width;
        if (config->title_pos == POSITION_NONE && box_width > total_width) {
            max_width = box_width;
        }
        // Left character - use l_junct if title starts at left edge, if center-aligned and clipped to table width, or if right-aligned and clipped to table width
        if (title_padding == 0 || (config->title_pos == POSITION_CENTER && box_width >= total_width) || (config->title_pos == POSITION_RIGHT && box_width >= total_width)) {
            printf("%s", config->theme.l_junct);
        } else {
            printf("%s", config->theme.tl_corner);
        }
        current_pos = 1;
        int title_start = title_padding;
        int title_end = title_padding + box_width - 2;
        for (int i = current_pos; i < max_width; i++) {
            if (i == max_width - 1) {
                if (config->title_pos == POSITION_NONE && box_width > total_width) {
                    printf("%s", config->theme.br_corner); // Use bottom-right corner if title extends beyond table width with no position specified
                } else if (title_right_edge >= total_width - 1 || (config->title_pos == POSITION_RIGHT && box_width >= total_width)) {
                    printf("%s", config->theme.r_junct); // Use right junction if title box aligns with or is clipped to table right edge
                } else {
                    printf("%s", config->theme.tr_corner);
                }
            } else if (i == title_end + 1 && i < max_width - 1) {
                if (title_right_edge >= total_width - 1 || (config->title_pos == POSITION_RIGHT && box_width >= total_width)) {
                    printf("%s", config->theme.r_junct); // Use right junction if title box aligns with or is clipped to table right edge
                } else {
                    int is_column_line = 0;
                    for (int p = 0; p < col_pos_count; p++) {
                        if (i == column_positions[p] + 1) {
                            printf("%s", config->theme.t_junct); // Use top junction as cross junction if aligns with column line
                            is_column_line = 1;
                            break;
                        }
                    }
                    if (!is_column_line) {
                        printf("%s", config->theme.b_junct); // Use bottom junction if not aligned with column line
                    }
                }
            } else if (i == title_start && title_start > 0 && title_start < total_width) {
                if (config->title_pos == POSITION_RIGHT || config->title_pos == POSITION_CENTER) {
                    int is_column_line = 0;
                    for (int p = 0; p < col_pos_count; p++) {
                        if (i == column_positions[p] + 1) {
                            printf("%s", config->theme.cross); // Use cross junction if aligns with column line
                            is_column_line = 1;
                            break;
                        }
                    }
                    if (!is_column_line) {
                        printf("%s", config->theme.b_junct); // Use bottom junction for right-aligned or center-aligned title starting after table left edge if not aligned with column line
                    }
                } else {
                    printf("%s", config->theme.b_junct);
                }
            } else if (i == total_width - 1 && config->title_pos == POSITION_NONE && box_width > total_width) {
                printf("%s", config->theme.t_junct); // Use top junction where table ends before title's end when no position is specified
            } else {
                int is_junction = 0;
                for (int p = 0; p < col_pos_count; p++) {
                    if (i == column_positions[p] + 1) {
                        if (i == title_start + 1 || i == title_end) {
                            printf("%s", config->theme.b_junct);
                        } else {
                            printf("%s", config->theme.t_junct);
                        }
                        is_junction = 1;
                        break;
                    }
                }
                if (!is_junction) {
                    printf("%s", config->theme.h_line);
                }
            }
        }
        current_pos = max_width;
    } else {
        printf("%s", config->theme.tl_corner);
        current_pos = 1;
        for (int j = 0; j < config->column_count; j++) {
            if (!config->columns[j].visible) continue;
            for (int w = 0; w < config->columns[j].width; w++) {
                printf("%s", config->theme.h_line);
                current_pos++;
            }
            if (j < config->column_count - 1) {
                int next_col_visible = 0;
                for (int k = j + 1; k < config->column_count; k++) {
                    if (config->columns[k].visible) {
                        next_col_visible = 1;
                        break;
                    }
                }
                if (next_col_visible) {
                    printf("%s", config->theme.t_junct);
                    current_pos++;
                }
            }
        }
        printf("%s", config->theme.tr_corner);
    }
    free(column_positions);
    printf("%s\n", config->theme.text_color);
}
