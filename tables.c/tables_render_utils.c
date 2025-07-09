/*
 * tables_render_utils.c - Utility functions for table rendering
 * Contains helper functions for string handling and text wrapping.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tables_render_utils.h"

/*
 * Helper function to duplicate a string, returning NULL if input is NULL
 */
char *strdup_safe(const char *str) {
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
    extern int debug_mode;
    if (text == NULL || strlen(text) == 0 || width <= 0) {
        *line_count = 1;
        char **lines = malloc(sizeof(char *));
        if (lines == NULL) return NULL;
        lines[0] = strdup("");
        if (debug_mode) {
            fprintf(stderr, "Debug: wrap_text empty or invalid input, returning single empty line\n");
        }
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
    if (debug_mode) {
        fprintf(stderr, "Debug: wrap_text allocated initial memory for lines and current_line\n");
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
    if (debug_mode) {
        fprintf(stderr, "Debug: wrap_text completed, returning %d lines\n", *line_count);
    }
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
        if (((i + delimiter_len <= text_len) && (strncmp(text + i, delimiter, delimiter_len) == 0)) || c == '\0') {
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
 * Process a string to evaluate dynamic commands within $() and return the result
 * Forks a process to execute the command and captures its output
 */
char *evaluate_dynamic_string(const char *input) {
    if (input == NULL || strlen(input) == 0) {
        return strdup("");
    }

    char *result = strdup(input);
    if (result == NULL) {
        fprintf(stderr, "Error: Memory allocation failed for string duplication\n");
        return NULL;
    }

    char *current = result;
    char *new_result = NULL;
    size_t result_len = strlen(result);
    size_t new_len = 0;

    while (current && *current) {
        char *start = strstr(current, "$(");
        if (start == NULL) {
            break;
        }

        char *end = strchr(start + 2, ')');
        if (end == NULL) {
            break;
        }

        size_t cmd_len = end - start - 2;
        char *cmd = malloc(cmd_len + 1);
        if (cmd == NULL) {
            free(result);
            return NULL;
        }
        strncpy(cmd, start + 2, cmd_len);
        cmd[cmd_len] = '\0';

        // Execute command and capture output
        char *cmd_output = NULL;
        FILE *fp = popen(cmd, "r");
        if (fp) {
            char buffer[1024];
            size_t output_len = 0;
            size_t capacity = 1024;
            cmd_output = malloc(capacity);
            if (cmd_output) {
                while (fgets(buffer, sizeof(buffer), fp)) {
                    size_t len = strlen(buffer);
                    if (output_len + len >= capacity) {
                        capacity *= 2;
                        char *new_output = realloc(cmd_output, capacity);
                        if (new_output == NULL) {
                            free(cmd_output);
                            cmd_output = NULL;
                            break;
                        }
                        cmd_output = new_output;
                    }
                    strcpy(cmd_output + output_len, buffer);
                    output_len += len;
                }
                // Remove trailing newline if present
                if (output_len > 0 && cmd_output[output_len - 1] == '\n') {
                    cmd_output[output_len - 1] = '\0';
                }
            }
            pclose(fp);
        }

        free(cmd);

        // Calculate lengths
        size_t prefix_len = start - result;
        size_t suffix_len = result_len - (end - result + 1);
        size_t output_len = (cmd_output ? strlen(cmd_output) : 0);
        new_len = prefix_len + output_len + suffix_len + 1;

        // Build new result
        new_result = malloc(new_len);
        if (new_result == NULL) {
            free(result);
            free(cmd_output);
            return NULL;
        }

        if (prefix_len > 0) {
            strncpy(new_result, result, prefix_len);
        }
        if (cmd_output && output_len > 0) {
            strcpy(new_result + prefix_len, cmd_output);
        }
        if (suffix_len > 0) {
            strcpy(new_result + prefix_len + output_len, end + 1);
        }
        new_result[new_len - 1] = '\0';

        free(result);
        free(cmd_output);
        result = new_result;
        result_len = new_len - 1;
        current = result + prefix_len + output_len;
    }

    return result;
}

/*
 * Replace color placeholders like {RED}, {NC}, etc., with ANSI escape codes
 */
char *replace_color_placeholders(const char *input) {
    if (input == NULL || strlen(input) == 0) {
        return strdup("");
    }

    // Define color mappings
    const char *color_map[][2] = {
        {"{RED}", "\033[0;31m"},
        {"{BLUE}", "\033[0;34m"},
        {"{GREEN}", "\033[0;32m"},
        {"{YELLOW}", "\033[0;33m"},
        {"{CYAN}", "\033[0;36m"},
        {"{MAGENTA}", "\033[0;35m"},
        {"{BOLD}", "\033[1m"},
        {"{DIM}", "\033[2m"},
        {"{UNDERLINE}", "\033[4m"},
        {"{NC}", "\033[0m"}
    };
    const int color_map_size = sizeof(color_map) / sizeof(color_map[0]);

    char *result = strdup(input);
    if (result == NULL) {
        fprintf(stderr, "Error: Memory allocation failed for string duplication\n");
        return NULL;
    }

    for (int i = 0; i < color_map_size; i++) {
        const char *placeholder = color_map[i][0];
        const char *ansi_code = color_map[i][1];
        char *current = result;
        char *new_result = NULL;
        size_t result_len = strlen(result);
        size_t placeholder_len = strlen(placeholder);
        size_t ansi_len = strlen(ansi_code);

        while (current && *current) {
            char *match = strstr(current, placeholder);
            if (match == NULL) {
                break;
            }

            size_t prefix_len = match - result;
            size_t suffix_len = result_len - prefix_len - placeholder_len;
            size_t new_len = prefix_len + ansi_len + suffix_len + 1;

            new_result = malloc(new_len);
            if (new_result == NULL) {
                free(result);
                return NULL;
            }

            if (prefix_len > 0) {
                strncpy(new_result, result, prefix_len);
            }
            strcpy(new_result + prefix_len, ansi_code);
            if (suffix_len > 0) {
                strcpy(new_result + prefix_len + ansi_len, match + placeholder_len);
            }
            new_result[new_len - 1] = '\0';

            free(result);
            result = new_result;
            result_len = new_len - 1;
            current = result + prefix_len + ansi_len;
        }
    }

    return result;
}
