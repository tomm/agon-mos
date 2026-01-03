#ifndef GLOBALS_H
#define GLOBALS_H

#include "defines.h"

// Declarations in globals.asm
extern volatile uint8_t scrrows;
extern volatile uint8_t scrcols;
extern volatile uint8_t scrcolours;
extern volatile uint8_t vpd_protocol_flags;
extern volatile uint8_t cursorX;
extern volatile uint8_t cursorY;
extern volatile uint8_t scrpixelIndex;
extern volatile uint8_t rtc_enable;
extern volatile char gp;
extern volatile char keycode;
extern volatile uint8_t keyascii;
extern volatile uint8_t keydown;
extern volatile uint8_t keycount;
extern char hardReset; // 1 = hard cpu reset, 0 = soft reset
extern uint8_t history_no;
extern uint8_t history_size;

#endif		       /* GLOBALS_H */
