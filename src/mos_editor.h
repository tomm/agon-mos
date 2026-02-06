/*
 * Title:			AGON MOS - MOS line editor
 * Author:			Dean Belfield
 * Created:			18/09/2022
 * Last Updated:	22/03/2023
 *
 * Modinfo:
 * 28/09/2022:		Added clear parameter to mos_EDITLINE
 * 22/03/2023:		Added defines for command history
 */

#ifndef MOS_EDITOR_H
#define MOS_EDITOR_H

#include "defines.h"
#include "vec.h"

enum TabExpansionType : uint8_t {
	ExpandNormal,
	ExpandDirectory,
};

typedef struct tab_expansion_t {
	enum TabExpansionType type;
	char *expansion;
} tab_expansion_t;

struct tab_expansion_context {
	int num_matches;
	char *cmdline;
	int cmdline_insertpos;
	char expansion[128];
	Vec /*<tab_expansion_t>*/ candidates;
};

void notify_tab_expansion(struct tab_expansion_context *ctx, enum TabExpansionType type, const char *fullExpansion, int fullExpansionLen, const char *expansion, int expansionLen);

#define cmd_historyWidth 255
#define cmd_historyDepth 16

uint24_t mos_EDITLINE(char *filename, int bufferLength, uint8_t clear);

void editHistoryInit();

extern char *hotkey_strings[12];

#endif /* MOS_EDITOR_H */
