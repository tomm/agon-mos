#include "uart.h"
#include "version.h"
#include <stdio.h>
#include <string.h>

extern volatile uint8_t scrcolours, scrpixelIndex; // In globals.asm

static uint8_t quickrand(void)
{
	uint8_t out;
	asm volatile("ld a,r\n"
		     : "=%a"(out));
	return out;
}

static void rainbow_msg(char* msg)
{
	uint8_t i = quickrand() & (scrcolours - 1);
	if (strcmp(msg, "Rainbow") != 0) {
		printf("%s", msg);
		return;
	}
	if (i == 0)
		i++;
	for (; *msg; msg++) {
		putch(17);
		putch(i);
		putch(*msg);
		i = (i + 1 < scrcolours) ? i + 1 : 1;
	}
	putch(17);
	putch(15);
}

void mos_bootmsg(void)
{
	printf("Agon ");
	rainbow_msg(VERSION_VARIANT);
	printf(" MOS " VERSION_GITREF);

// Show version subtitle, if we have one
#ifdef VERSION_SUBTITLE
	printf(" ");
	rainbow_msg(VERSION_SUBTITLE);
#endif

	printf("\n\r\n\r");
}
