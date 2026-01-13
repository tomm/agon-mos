/*
 * Title:			AGON MOS - Additional string functions
 * Author:			Leigh Brown, HeathenUK, and others
 * Created:			24/05/2023
 */

#include "umm_malloc.h"
#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define MIN(a, b) ((a) < (b) ? (a) : (b))

// Alternative to missing strnlen() in ZDS libraries
size_t mos_strnlen(const char *s, size_t maxlen)
{
	size_t len = 0;
	while (len < maxlen && s[len] != '\0') {
		len++;
	}
	return len;
}

// Alternative to missing strdup() in ZDS libraries
char *mos_strdup(const char *s)
{
	char *d = umm_malloc(strlen(s) + 1); // Allocate memory
	if (d != NULL) {
		strcpy(d, s);		     // Copy the string
	}
	return d;
}

// Alternative to missing strndup() in ZDS libraries
char *mos_strndup(const char *s, size_t n)
{
	size_t len = mos_strnlen(s, n);
	char *d = umm_malloc(len + 1); // Allocate memory for length plus null terminator

	if (d != NULL) {
		strncpy(d, s, len);    // Copy up to len characters
		d[len] = '\0';	       // Null-terminate the string
	}

	return d;
}

void strinsert(char *dest, const char *src, int insert_loc, int dest_maxlen)
{
	int src_len = strlen(src);
	int dest_tail_len = strlen(dest + insert_loc) + 1;

	int count = MIN(dest_tail_len, dest_maxlen - insert_loc - src_len);
	if (count > 0) {
		memmove(dest + insert_loc + src_len,
		    dest + insert_loc, count);
	}

	count = MIN(src_len, dest_maxlen - insert_loc - 1);
	if (count > 0) {
		memcpy(dest + insert_loc, src, count);
	}

	dest[dest_maxlen - 1] = 0;
}
