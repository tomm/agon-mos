#ifndef Z80_IO_H
#define Z80_IO_H

#include <stdint.h>

/* io_in and io_out look weird, but there are reasons... */
static inline uint8_t io_in(uint8_t addr)
{
	uint8_t out;
	asm volatile(
	    "ld b,0\n"
	    "in b,(c)\n"
	    :"=bc"(out)
	    :"c"(addr)
	);
	return out;
}

static inline void io_out(uint8_t addr, uint8_t value)
{
	asm volatile(
	    "ld a,b\n"
	    "ld b,0\n"
	    "out (c),e\n"
	    "ld b,a\n"
	    :
	    :"e"(value),"c"(addr)
	    :"a"
	);
}

static inline void io_setreg(uint8_t addr, uint8_t bits)
{
	io_out(addr, io_in(addr) | bits);
}

static inline void io_resetreg(uint8_t addr, uint8_t bits)
{
	io_out(addr, io_in(addr) & (0xff ^ bits));
}

#endif /* Z80_IO_H */
