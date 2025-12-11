#ifndef CONSOLE_H
#define CONSOLE_H

#include <stdint.h>

struct console_driver_t {
	void (*get_cursor_pos)();
	void (*get_mode_information)();
	void (*read_palette)(uint8_t entry, bool wait);
};

extern void console_enable_fb();
extern void console_enable_vdp();

extern struct console_driver_t vdp_console;
extern struct console_driver_t fb_console;
extern struct console_driver_t *active_console;

#endif /* CONSOLE_H */
