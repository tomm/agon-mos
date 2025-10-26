#include <stdio.h>
#include "defines.h"
#include "mos.h"
#include "console.h"
#include "uart.h"
#include "timer.h"

extern volatile BYTE vpd_protocol_flags;		// In globals.asm
extern BYTE cursorX;
extern BYTE cursorY;
extern BYTE scrcols;

// Get the current cursor position from the VPD
//
void vdpGetCursorPos() {
	vpd_protocol_flags &= 0xFE;					// Clear the semaphore flag
	putch(23);									// Request the cursor position
	putch(0);
	putch(VDP_cursor);
	wait_VDP(0x01);								// Wait until the semaphore has been set, or a timeout happens
}

// Get the current screen dimensions from the VDU
//
void vdpGetModeInformation() {
	vpd_protocol_flags &= 0xEF;					// Clear the semaphore flag
	putch(23);
	putch(0);
	putch(VDP_mode);
	wait_VDP(0x10);								// Wait until the semaphore has been set, or a timeout happens
}

// Get palette entry
//
void vdpReadPalette(BYTE entry, BOOL wait) {
	vpd_protocol_flags &= 0xFB;					// Clear the semaphore flag
	putch(23);
	putch(0);
	putch(VDP_palette);
	putch(entry);
	if (wait) {
		wait_VDP(0x04);							// Wait until the semaphore has been set, or a timeout happens
	}
}

void fbGetCursorPos() {
}

void fbGetModeInformation() {
}

void fbReadPalette(BYTE entry, BOOL wait) {
}

struct console_driver_t vdp_console = {
	.get_cursor_pos = &vdpGetCursorPos,
	.get_mode_information = &vdpGetModeInformation,
	.read_palette = &vdpReadPalette,
};

struct console_driver_t fb_console = {
	.get_cursor_pos = &fbGetCursorPos,
	.get_mode_information = &fbGetModeInformation,
	.read_palette = &fbReadPalette,
};

struct console_driver_t *active_console = &vdp_console;

void console_enable_fb(void *fb_base, int width, int height)
{
	if (fb_base == 0) {
		active_console = &vdp_console;
	} else {
		active_console = &fb_console;
		printf("FB console: %d x %d pixels at 0x%x\r\n", width, height, (unsigned int)fb_base);
	}
}
