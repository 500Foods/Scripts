/*
 * tables_render_utils.h - Header file for utility functions used in table rendering
 */

#ifndef TABLES_RENDER_UTILS_H
#define TABLES_RENDER_UTILS_H

/*
 * Helper function to duplicate a string, returning NULL if input is NULL
 */
char *strdup_safe(const char *str);

/*
 * Calculate display width of text, accounting for ANSI escape codes
 */
int get_display_width(const char *text);

/*
 * Wrap text to a specified width, returning an array of lines
 */
char **wrap_text(const char *text, int width, int *line_count);

/*
 * Wrap text based on a delimiter, returning an array of lines
 */
char **wrap_text_delimiter(const char *text, int width, const char *delimiter, int *line_count);

/*
 * Free memory allocated for wrapped text lines
 */
void free_wrapped_text(char **lines, int line_count);

/*
 * Process a string to evaluate dynamic commands within $() and return the result
 */
char *evaluate_dynamic_string(const char *input);

/*
 * Replace color placeholders like {RED}, {NC}, etc., with ANSI escape codes
 */
char *replace_color_placeholders(const char *input);

#endif /* TABLES_RENDER_UTILS_H */
