#ifndef FBCONSOLE_H
#define FBCONSOLE_H

#include <stdint.h>

#define FBMODE_FLAG_SLOW (1<<0)
#define FBMODE_FLAG_15KHZ (1<<1)
#define FBMODE_FLAG_31KHZ (1<<2)
#define FBMODE_FLAG_30HZ (1<<3)
#define FBMODE_FLAG_60HZ (1<<4)

struct __attribute__((packed)) fbmodeinfo_t {
	uint24_t scanline_isr;
	uint24_t clockcycles_per_scanline_div_4;
	uint24_t width;
	uint24_t height;
	uint24_t scan_multiplier;
	uint8_t flags;
};

extern int start_fbterm(int mode, void *fb_base, void *fb_scanline_offsets);
extern uint8_t fb_driverversion(void);
extern struct fbmodeinfo_t *fb_lookupmode(int mode);
extern uint8_t fb_curs_x;
extern uint8_t fb_curs_y;
extern uint8_t fbterm_width;
extern uint8_t fbterm_height;

#endif /* FBCONSOLE_H */
