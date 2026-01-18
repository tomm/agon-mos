/*
 * Title:			AGON MOS - Additional string functions
 * Author:			Leigh Brown
 * Created:			24/05/2023
 * Last Updated:	24/05/2023
 *
 * Modinfo:
 */

#ifndef STRINGS_H
#define STRINGS_H

// Alternative to missing strdup() in ZDS libraries
char *mos_strdup(const char *s);

// Alternative to missing strndup() in ZDS libraries
char *mos_strndup(const char *s, size_t n);

void strbuf_append(char *buf, int buf_capacity, const char *str_to_append, int max_chars_to_append);
void strbuf_insert(char *buf, int buf_capacity, const char *src, int insert_loc);

#endif // STRINGS_H
