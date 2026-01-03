#ifndef FORMATTING_H
#define FORMATTING_H

#include "defines.h"

extern bool paginated_exit;

void paginated_start(bool enabled);
void paginated_write(const char* buf, int len);
void paginated_printf(const char* format, ...) __attribute__((format(printf, 1, 2)));
void paginated_putch(uint8_t c);

void set_color(uint8_t col);
uint8_t get_primary_color();
uint8_t get_secondary_color();

#endif /* FORMATTING_H */
