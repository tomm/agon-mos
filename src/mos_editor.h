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

struct tab_expansion_context {
	int num_matches;
	char *cmdline;
	int cmdline_insertpos;
	char expansion[128];
};

enum TabExpansionType : uint8_t {
	ExpandNormal,
	ExpandDirectory,
};

void tab_expansion_callback(struct tab_expansion_context *ctx, enum TabExpansionType type, const char *fullExpansion, int fullExpansionLen, const char *expansion, int expansionLen);

enum TabCompleteState : uint8_t {
	TabCompleteInitial,
	TabCompleteWait,
	TabCompleteShowOptions
};

extern enum TabCompleteState tab_complete_state;

#define cmd_historyWidth 255
#define cmd_historyDepth 16

uint24_t mos_EDITLINE(char *filename, int bufferLength, uint8_t clear);

void editHistoryInit();
void editHistoryPush(char *buffer);
bool editHistoryUp(char *buffer, int insertPos, int len, int limit);
bool editHistoryDown(char *buffer, int insertPos, int len, int limit);
bool editHistorySet(char *buffer, int insertPos, int len, int limit, int index);

extern char *hotkey_strings[12];

#endif /* MOS_EDITOR_H */
