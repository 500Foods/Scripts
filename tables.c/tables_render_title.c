/*
 * tables_render_title.c - Functions for rendering the title box of a table
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tables_render_title.h"
#include "tables_render_utils.h"
#include "tables_render_layout.h"

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

    char *display_title = processed_title;
    int title_width = get_display_width(display_title);
    int box_width = title_width + 4;

    int max_title_width = 0;
    if (config->title_pos == POSITION_FULL) {
        max_title_width = total_width > 4 ? total_width - 4 : 0;
    } else {
        max_title_width = total_width > 4 ? total_width - 4 : 0;
    }

    if (box_width > total_width && config->title_pos != POSITION_NONE) {
        char *clipped_title = clip_text_to_width(display_title, max_title_width);
        if (clipped_title) {
            if (display_title != processed_title) {
                free(display_title);
            }
            display_title = clipped_title;
        }
    }

    title_width = get_display_width(display_title);
    if (config->title_pos == POSITION_FULL) {
        box_width = total_width;
    } else if (config->title_pos == POSITION_NONE) {
        box_width = title_width + 4;
    } else {
        box_width = title_width + 4;
        if (box_width > total_width) {
            box_width = total_width;
        }
    }

    int title_padding = 0;
    if (config->title_pos == POSITION_CENTER) {
        title_padding = (total_width - box_width) / 2;
    } else if (config->title_pos == POSITION_RIGHT) {
        title_padding = total_width - box_width;
    }

    printf("%s%*s%s", config->theme.border_color, title_padding, "", config->theme.tl_corner);
    for (int i = 0; i < box_width - 2; i++) {
        printf("%s", config->theme.h_line);
    }
    printf("%s%s\n", config->theme.tr_corner, config->theme.text_color);

    printf("%s%*s%s", config->theme.border_color, title_padding, "", config->theme.v_line);
    int available_width = box_width - 2;
    char *clipped_text = clip_text(display_title, available_width, config->title_pos);
    
    int text_width = get_display_width(clipped_text);
    int left_padding = 1;
    int right_padding = 1;

    if (config->title_pos == POSITION_FULL) {
        left_padding = (box_width - text_width) / 2;
        right_padding = box_width - text_width - left_padding;
    }

    printf("%*s%s%s%*s", left_padding, "", config->theme.caption_color, clipped_text, right_padding, "");
    printf("%s%s\n", config->theme.border_color, config->theme.v_line);
    
    free(clipped_text);
    if (display_title != processed_title) {
        free(display_title);
    }
    free(processed_title);
}

void render_top_border_with_title(TableConfig *config, int total_width, int title_present, int title_padding, int box_width) {
    printf("%s", config->theme.border_color);
    int *column_positions = malloc((config->column_count - 1) * sizeof(int));
    int col_pos_count = 0;
    if (column_positions) {
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
                col_width_sum++;
            }
        }
    }

    if (title_present) {
        int title_start = title_padding;
        int title_end = title_padding + box_width - 1;

        for (int i = 0; i < total_width; i++) {
            int is_col_junct = 0;
            if (column_positions) {
                for (int k = 0; k < col_pos_count; k++) {
                    if (i == column_positions[k] + 1) {
                        is_col_junct = 1;
                        break;
                    }
                }
            }

            if (i == 0) {
                printf("%s", (title_start == 0) ? config->theme.l_junct : config->theme.tl_corner);
            } else if (i == total_width - 1) {
                printf("%s", (title_end >= total_width - 1) ? config->theme.r_junct : config->theme.tr_corner);
            } else if (i == title_start) {
                printf("%s", is_col_junct ? config->theme.cross : config->theme.b_junct);
            } else if (i == title_end) {
                printf("%s", is_col_junct ? config->theme.cross : config->theme.b_junct);
            } else if (i > title_start && i < title_end) {
                printf("%s", is_col_junct ? config->theme.t_junct : config->theme.h_line);
            } else {
                printf("%s", is_col_junct ? config->theme.t_junct : config->theme.h_line);
            }
        }
    } else {
        printf("%s", config->theme.tl_corner);
        for (int i = 1; i < total_width - 1; i++) {
            int is_col_junct = 0;
            if (column_positions) {
                for (int k = 0; k < col_pos_count; k++) {
                    if (i == column_positions[k] + 1) {
                        is_col_junct = 1;
                        break;
                    }
                }
            }
            printf("%s", is_col_junct ? config->theme.t_junct : config->theme.h_line);
        }
        printf("%s", config->theme.tr_corner);
    }

    if (column_positions) {
        free(column_positions);
    }
    printf("%s\n", config->theme.text_color);
}
