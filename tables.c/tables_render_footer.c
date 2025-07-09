/*
 * tables_render_footer.c - Functions for rendering the footer box of a table
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tables_render_footer.h"
#include "tables_render_utils.h"

/*
 * Render the footer box with proper borders and positioning
 */
void render_footer(TableConfig *config, int total_width) {
    int footer_present = (config->footer && strlen(config->footer) > 0);
    if (!footer_present) return;

    char *evaluated_footer = evaluate_dynamic_string(config->footer);
    if (evaluated_footer == NULL) {
        fprintf(stderr, "Error: Failed to evaluate dynamic footer string\n");
        evaluated_footer = strdup(config->footer ? config->footer : "");
        if (evaluated_footer == NULL) {
            fprintf(stderr, "Error: Memory allocation failed for footer string\n");
            return;
        }
    }

    char *processed_footer = replace_color_placeholders(evaluated_footer);
    if (processed_footer == NULL) {
        fprintf(stderr, "Error: Failed to process color placeholders in footer\n");
        processed_footer = strdup(evaluated_footer);
        if (processed_footer == NULL) {
            fprintf(stderr, "Error: Memory allocation failed for processed footer string\n");
            free(evaluated_footer);
            return;
        }
    }
    free(evaluated_footer);

    int footer_width = get_display_width(processed_footer);
    int box_width = footer_width + 4; // Add padding for box borders and internal padding
    // Limit box_width to total_width for non-full width footers
    if (config->footer_pos != POSITION_FULL && box_width > total_width) {
        box_width = total_width;
    }
    int footer_padding = 0;
    int footer_right_edge = 0;

    if (config->footer_pos == POSITION_CENTER) {
        footer_padding = (total_width - box_width) / 2;
        footer_right_edge = footer_padding + box_width - 1;
    } else if (config->footer_pos == POSITION_RIGHT) {
        footer_padding = total_width - box_width;
        footer_right_edge = total_width - 1;
    } else if (config->footer_pos == POSITION_FULL) {
        box_width = total_width;
        footer_padding = 0;
        footer_right_edge = total_width - 1;
    } else { // POSITION_LEFT or default
        footer_padding = 0;
        footer_right_edge = box_width - 1;
    }

    // Bottom border of table integrating with footer will be rendered after adjustments

    // Ensure box_width does not exceed total_width for rendering and clipping
    if (box_width > total_width && config->footer_pos != POSITION_FULL) {
        box_width = total_width;
        footer_padding = 0;
        footer_right_edge = total_width - 1;
    }
    // Footer text line with clipping if necessary
    char *display_footer = processed_footer;
    int footer_text_width = get_display_width(processed_footer); // Use display width for clipping
    int max_footer_width = box_width - 4; // Account for borders and padding, use final box_width after constraints
    if (footer_text_width > max_footer_width) {
        display_footer = malloc(strlen(processed_footer) + 1);
        if (display_footer) {
            if (config->footer_pos == POSITION_CENTER || config->footer_pos == POSITION_FULL) {
                // For center or full alignment, clip from the right to match Bash behavior
                int current_width = 0;
                int i = 0;
                while (processed_footer[i] != '\0' && current_width < max_footer_width) {
                    if (processed_footer[i] == '\033') {
                        // Skip ANSI escape sequences
                        while (processed_footer[i] != '\0' && processed_footer[i] != 'm') {
                            i++;
                        }
                        if (processed_footer[i] == 'm') {
                            i++;
                        }
                    } else {
                        current_width++;
                        i++;
                    }
                }
                strncpy(display_footer, processed_footer, i);
                display_footer[i] = '\0';
            } else if (config->footer_pos == POSITION_RIGHT) {
                // For right alignment, clip from the left to show the rightmost content
                int total_len = strlen(processed_footer);
                int start = total_len;
                int current_width = 0;
                for (int i = total_len - 1; i >= 0 && current_width < max_footer_width; i--) {
                    if (i > 0 && processed_footer[i] == 'm' && processed_footer[i-1] == '\033') {
                        // Handle ANSI escape sequences from the end
                        while (i > 0 && processed_footer[i] != '\033') {
                            i--;
                        }
                        if (i > 0) {
                            i--; // Move to the start of the escape sequence
                        }
                    } else {
                        current_width++;
                    }
                    if (current_width <= max_footer_width) {
                        start = i;
                    }
                }
                if (start < 0) start = 0;
                strncpy(display_footer, processed_footer + start, total_len - start);
                display_footer[total_len - start] = '\0';
                // Ensure the display width is strictly limited to max_footer_width
                current_width = get_display_width(display_footer);
                if (current_width > max_footer_width) {
                    int new_i = 0;
                    current_width = 0;
                    while (display_footer[new_i] != '\0' && current_width < max_footer_width) {
                        if (display_footer[new_i] == '\033') {
                            while (display_footer[new_i] != '\0' && display_footer[new_i] != 'm') {
                                new_i++;
                            }
                            if (display_footer[new_i] == 'm') {
                                new_i++;
                            }
                        } else {
                            current_width++;
                            new_i++;
                        }
                    }
                    display_footer[new_i] = '\0';
                }
            } else {
                // Default or left alignment clip from the right
                int current_width = 0;
                int i = 0;
                while (processed_footer[i] != '\0' && current_width < max_footer_width) {
                    if (processed_footer[i] == '\033') {
                        // Skip ANSI escape sequences
                        while (processed_footer[i] != '\0' && processed_footer[i] != 'm') {
                            i++;
                        }
                        if (processed_footer[i] == 'm') {
                            i++;
                        }
                    } else {
                        current_width++;
                        i++;
                    }
                }
                strncpy(display_footer, processed_footer, i);
                display_footer[i] = '\0';
            }
        }
    }
    // Adjust box_width based on the actual display footer width if it's clipped
    int display_footer_width = get_display_width(display_footer);
    if (box_width > display_footer_width + 4 && config->footer_pos != POSITION_FULL) {
        box_width = display_footer_width + 4;
        if (config->footer_pos == POSITION_CENTER) {
            footer_padding = (total_width - box_width) / 2;
            footer_right_edge = footer_padding + box_width - 1;
        } else if (config->footer_pos == POSITION_RIGHT) {
            footer_padding = total_width - box_width;
            footer_right_edge = total_width - 1;
        } else {
            footer_padding = 0;
            footer_right_edge = box_width - 1;
        }
    }
    // Update footer_end based on the adjusted box_width
    int footer_end = footer_padding + box_width - 2;

    // Bottom border of table integrating with footer if present
    printf("%s", config->theme.border_color);
    int current_pos = 0;
    if (footer_present) {
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
        // Always start from the left-most position of the table
        current_pos = 0;
        // Extend beyond table width if footer position is none
        int max_width = total_width;
        if (config->footer_pos == POSITION_NONE && box_width > total_width) {
            max_width = box_width;
        }
        // Start rendering from the left edge of the table
        if (footer_padding == 0 || (config->footer_pos == POSITION_FULL && box_width >= total_width)) {
            printf("%s", config->theme.l_junct); // Use left junction if footer starts at left edge or is full width
        } else {
            printf("%s", config->theme.bl_corner); // Otherwise start with bottom-left corner
        }
        current_pos = 1;
        // Render footer top border with junctions at column positions
        int footer_start = footer_padding;
        for (int i = current_pos; i < max_width; i++) {
            if (i == max_width - 1) {
                if (config->footer_pos == POSITION_NONE && box_width > total_width) {
                    printf("%s", config->theme.tr_corner); // Use top-right corner if footer extends beyond table width with no position specified
                } else if (footer_right_edge >= total_width - 1 || (config->footer_pos == POSITION_RIGHT && box_width >= total_width)) {
                    printf("%s", config->theme.r_junct); // Use right junction if footer box aligns with or is clipped to table right edge
                } else {
                    printf("%s", config->theme.br_corner);
                }
            } else if (i == footer_end + 1 && i < max_width - 1) {
                if (footer_right_edge >= total_width - 1 || (config->footer_pos == POSITION_RIGHT && box_width >= total_width)) {
                    printf("%s", config->theme.r_junct); // Use right junction if footer box aligns with or is clipped to table right edge
                } else {
                    int is_column_line = 0;
                    for (int p = 0; p < col_pos_count; p++) {
                        if (i == column_positions[p] + 1) {
                            printf("%s", config->theme.cross); // Use cross junction if aligns with column line
                            is_column_line = 1;
                            break;
                        }
                    }
                    if (!is_column_line) {
                        printf("%s", config->theme.t_junct); // Use top junction if not aligned with column line
                    }
                }
            } else if (i == footer_start && footer_start > 0 && footer_start < total_width) {
                if (config->footer_pos == POSITION_RIGHT || config->footer_pos == POSITION_CENTER) {
                    int is_column_line = 0;
                    for (int p = 0; p < col_pos_count; p++) {
                        if (i == column_positions[p] + 1) {
                            printf("%s", config->theme.cross); // Use cross junction if aligns with column line
                            is_column_line = 1;
                            break;
                        }
                    }
                    if (!is_column_line) {
                        printf("%s", config->theme.t_junct); // Use top junction for right-aligned or center-aligned footer starting after table left edge if not aligned with column line
                    }
                } else {
                    printf("%s", config->theme.t_junct);
                }
            } else if (i == total_width - 1 && config->footer_pos == POSITION_NONE && box_width > total_width) {
                printf("%s", config->theme.b_junct); // Use bottom junction where table ends before footer's end when no position is specified
            } else {
                int is_junction = 0;
                for (int p = 0; p < col_pos_count; p++) {
                    if (i == column_positions[p] + 1) {
                        printf("%s", config->theme.b_junct); // Use bottom junction for column lines
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
        free(column_positions);
    } else {
        printf("%s", config->theme.bl_corner);
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
                    printf("%s", config->theme.b_junct);
                    current_pos++;
                }
            }
        }
        printf("%s", config->theme.br_corner);
    }
    printf("%s\n", config->theme.text_color);
    printf("%s%*s%s%s %s %s%s\n", config->theme.border_color, footer_padding, "", config->theme.v_line, config->theme.footer_color, display_footer, config->theme.border_color, config->theme.v_line);
    if (display_footer != processed_footer) {
        free(display_footer);
    }
    free(processed_footer);

    // Bottom border of footer box
    printf("%s%*s%s", config->theme.border_color, footer_padding, "", config->theme.bl_corner);
    for (int i = 0; i < box_width - 2; i++) {
        printf("%s", config->theme.h_line);
    }
    printf("%s%s\n", config->theme.br_corner, config->theme.text_color);
}
