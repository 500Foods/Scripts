/*
 * tables_render.h - Header file for table rendering in the tables utility
 * Defines structures and function prototypes for rendering formatted tables.
 */

#ifndef TABLES_RENDER_H
#define TABLES_RENDER_H

#include "tables_config.h"
#include "tables_data.h"

/* Function prototypes */
void render_table(TableConfig *config, TableData *data);
void calculate_column_widths(TableConfig *config, TableData *data);
int get_display_width(const char *text);
char **wrap_text(const char *text, int width, int *line_count);
void free_wrapped_text(char **lines, int line_count);

#endif /* TABLES_RENDER_H */
