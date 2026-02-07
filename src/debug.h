#ifndef DEBUG_H
#define DEBUG_H

#ifdef DEBUG

#define kassert(condition)                          \
	{                                           \
		if (!(condition)) {                 \
			asm volatile("rst 0x38\n"); \
		}                                   \
	}
extern uint24_t stack_highwatermark;
void record_stack_highwatermark();
#define DEBUG_STACK() record_stack_highwatermark()

#else  /* !DEBUG */

#define kassert(condition)
#define DEBUG_STACK()

#endif /* DEBUG */

#endif /* DEBUG_H */
