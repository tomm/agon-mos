#ifndef FBCONSOLE_H
#define FBCONSOLE_H

#include <stdint.h>

extern int start_fbterm(int mode);
extern uint8_t fb_curs_x;
extern uint8_t fb_curs_y;
extern uint8_t fbterm_width;
extern uint8_t fbterm_height;

#endif /* FBCONSOLE_H */
