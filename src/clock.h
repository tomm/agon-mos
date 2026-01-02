/*
 * Title:			AGON MOS - Real Time Clock
 * Author:			Dean Belfield
 * Created:			09/03/2023
 * Last Updated:	26/09/2023
 *
 * Modinfo:
 * 15/03/2023:		Added rtc_getDateString, rtc_update
 * 26/09/2023:		Timestamps now packed into 6 bytes
 */

#ifndef RTC_H
#define RTC_H

#include "defines.h"

#define EPOCH_YEAR 1980

// RTC time structure
//
typedef struct {
	uint16_t year;
	uint8_t month;
	uint8_t day;
	uint8_t dayOfWeek;
	uint16_t dayOfYear;
	uint8_t hour;
	uint8_t minute;
	uint8_t second;
} vdp_time_t;

void init_rtc(); // In rtc.asm

void rtc_update();
void rtc_unpack(uint8_t* buffer, vdp_time_t* t);
void rtc_formatDateTime(char* buffer, vdp_time_t* t);

#endif		 /* RTC_H */
