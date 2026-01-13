/*
 * Title:			AGON MOS - MOS line editor
 * Author:			Dean Belfield
 * Created:			18/09/2022
 * Last Updated:	31/03/2023
 *
 * Modinfo:
 * 28/09/2022:		Added clear parameter to mos_EDITLINE
 * 20/02/2023:		Fixed mos_EDITLINE to handle the full CP-1252 character set
 * 09/03/2023:		Added support for virtual keys; improved editing functionality
 * 14/03/2023:		Tweaks ready for command history
 * 21/03/2023:		Improved backspace, and editing of long lines, after scroll, at bottom of screen
 * 22/03/2023:		Added a single-entry command line history
 * 31/03/2023:		Added timeout for VDP protocol
 */

#include "mos_editor.h"
#include "console.h"
#include "defines.h"
#include "ez80f92.h"
#include "formatting.h"
#include "globals.h"
#include "keyboard_buffer.h"
#include "mos.h"
#include "strings.h"
#include "timer.h"
#include "uart.h"
#include "umm_malloc.h"
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum TabCompleteState tab_complete_state;

// Storage for the command history
//
static char *cmd_history[cmd_historyDepth];

char *hotkey_strings[12] = {};

// Move cursor left
//
void doLeftCursor()
{
	active_console->get_cursor_pos();
	if (cursorX > 0) {
		putch(0x08);
	} else {
		while (cursorX < (scrcols - 1)) {
			putch(0x09);
			cursorX++;
		}
		putch(0x0B);
	}
}

// Move Cursor Right
//
void doRightCursor()
{
	active_console->get_cursor_pos();
	if (cursorX < (scrcols - 1)) {
		putch(0x09);
	} else {
		while (cursorX > 0) {
			putch(0x08);
			cursorX--;
		}
		putch(0x0A);
	}
}

// Insert a character in the input string
// Parameters:
// - buffer: Pointer to the line edit buffer
// - c: Character to insert
// - insertPos: Position in the input string to insert the character
// - len: Length of the input string (before the character is inserted)
// - limit: Max number of characters to insert
// Returns:
// - true if the character was inserted, otherwise false
//
bool insertCharacter(char *buffer, char c, int insertPos, int len, int limit)
{
	int i;
	int count = 0;

	if (len < limit) {
		putch(c);
		for (i = len; i >= insertPos; i--) {
			buffer[i + 1] = buffer[i];
		}
		buffer[insertPos] = c;
		for (i = insertPos + 1; i <= len; i++, count++) {
			putch(buffer[i]);
		}
		for (i = 0; i < count; i++) {
			doLeftCursor();
		}
		return 1;
	}
	return 0;
}

// Remove a character from the input string
// Parameters:
// - buffer: Pointer to the line edit buffer
// - insertPos: Position in the input string of the character to be deleted
// - len: Length of the input string before the character is deleted
// Returns:
// - true if the character was deleted, otherwise false
//
static bool deleteCharacter(char *buffer, int insertPos, int len)
{
	int i;
	int count = 0;
	if (insertPos > 0) {
		doLeftCursor();
		for (i = insertPos - 1; i < len; i++, count++) {
			uint8_t b = buffer[i + 1];
			buffer[i] = b;
			putch(b ? b : ' ');
		}
		for (i = 0; i < count; i++) {
			doLeftCursor();
		}
		return 1;
	}
	return 0;
}

static uint8_t deleteWord(char *buffer, int insertPos, int len)
{
	uint8_t num_deleted = 0;
	// First the trailing spaces
	while (insertPos > 0 && buffer[insertPos - 1] == ' ') {
		deleteCharacter(buffer, insertPos, len);
		num_deleted++;
		insertPos--;
	}
	// Then 1 'word'
	while (insertPos > 0 && buffer[insertPos - 1] != ' ') {
		deleteCharacter(buffer, insertPos, len);
		num_deleted++;
		insertPos--;
	}
	return num_deleted;
}

// handle HOME
//
static int gotoEditLineStart(int insertPos)
{
	while (insertPos > 0) {
		doLeftCursor();
		insertPos--;
	}
	return insertPos;
}

// handle END
//
static int gotoEditLineEnd(int insertPos, int len)
{
	while (insertPos < len) {
		doRightCursor();
		insertPos++;
	}
	return insertPos;
}

// remove current edit line
//
static void removeEditLine(char *buffer, int insertPos, int len)
{
	// goto start of line
	insertPos = gotoEditLineStart(insertPos);
	// set buffer to be spaces up to len
	memset(buffer, ' ', len);
	// print the buffer to erase old line from screen
	printf("%s", buffer);
	// clear the buffer
	buffer[0] = 0;
	gotoEditLineStart(len);
}

// Handle hotkey, if defined
// Returns:
// - 1 if the hotkey was handled, otherwise 0
//
static bool handleHotkey(uint8_t fkey, char *buffer, int bufferLength, int insertPos, int len)
{
	if (hotkey_strings[fkey] != NULL) {
		char *wildcardPos = strstr(hotkey_strings[fkey], "%s");

		if (wildcardPos == NULL) { // No wildcard in the hotkey string
			removeEditLine(buffer, insertPos, len);
			strcpy(buffer, hotkey_strings[fkey]);
			printf("%s", buffer);
		} else {
			uint8_t prefixLength = wildcardPos - hotkey_strings[fkey];
			uint8_t replacementLength = strlen(buffer);
			uint8_t suffixLength = strlen(wildcardPos + 2);
			char *result;

			if (prefixLength + replacementLength + suffixLength + 1 >= bufferLength) {
				// Exceeds max command length (256 chars)
				putch(0x07);							  // Beep
				return 0;
			}

			result = umm_malloc(prefixLength + replacementLength + suffixLength + 1); // +1 for null terminator
			if (!result) {
				// Memory allocation failed
				return 0;
			}

			strncpy(result, hotkey_strings[fkey], prefixLength); // Copy the portion preceding the wildcard to the buffer
			result[prefixLength] = '\0';			     // Terminate

			strcat(result, buffer);
			strcat(result, wildcardPos + 2);

			removeEditLine(buffer, insertPos, len);
			strcpy(buffer, result);
			printf("%s", buffer);

			umm_free(result);
		}
		return 1;
		// Key was present, so drop through to ASCII key handling
	}
	return 0;
}

void try_tab_expand_internal_cmd(struct tab_expansion_context *ctx);

void tab_expansion_callback(struct tab_expansion_context *ctx, enum TabExpansionType type, const char *fullExpansion, int fullExpansionLen, const char *expansion, int expansionLen)
{
	if (tab_complete_state == TabCompleteShowOptions) {
		if (ctx->num_matches == 0) printf("\r\n");
		uint8_t oldTextFg = active_console->get_fg_color_index();
		if (type != ExpandNormal) {
			set_color(get_secondary_color());
		}
		printf("%.*s ", fullExpansionLen, fullExpansion);
		set_color(oldTextFg);
	}
	if (ctx->num_matches == 0) {
		int count = MIN(expansionLen, sizeof(ctx->expansion) - 1);
		memcpy(ctx->expansion, expansion, count);
		ctx->expansion[count] = 0;
	} else {
		for (int j = 0; j < strlen(ctx->expansion); j++) {
			if (expansion[j] == 0 || toupper(ctx->expansion[j]) != toupper(expansion[j])) {
				ctx->expansion[j] = 0;
				break;
			}
		}
	}
	ctx->num_matches++;
}

static void try_tab_expand_bin_name(struct tab_expansion_context *ctx)
{
	FRESULT fr;
	DIR dj;
	FILINFO fno;

	char *search_term = umm_malloc(ctx->cmdline_insertpos + 6);
	search_term[0] = 0;
	strncat(search_term, ctx->cmdline, ctx->cmdline_insertpos);
	strcat(search_term, "*.bin");

	// Try local .bin
	fr = f_findfirst(&dj, &fno, "", search_term);
	while ((fr == FR_OK && fno.fname[0])) {
		tab_expansion_callback(ctx, ExpandNormal, fno.fname, strlen(fno.fname) - 4, fno.fname + ctx->cmdline_insertpos, strlen(fno.fname) - ctx->cmdline_insertpos - 4);
		fr = f_findnext(&dj, &fno);
	}

	if (strcmp(cwd, "/mos") != 0) {
		fr = f_findfirst(&dj, &fno, "/mos/", search_term);
		while (fr == FR_OK && fno.fname[0]) { // Now try MOSlets
			tab_expansion_callback(ctx, ExpandNormal, fno.fname, strlen(fno.fname) - 4, fno.fname + ctx->cmdline_insertpos, strlen(fno.fname) - ctx->cmdline_insertpos - 4);
			fr = f_findnext(&dj, &fno);
		}
	}

	if (strcmp(cwd, "/bin") != 0) {
		// Otherwise try /bin/
		fr = f_findfirst(&dj, &fno, "/bin/", search_term);
		while ((fr == FR_OK && fno.fname[0])) {
			tab_expansion_callback(ctx, ExpandNormal, fno.fname, strlen(fno.fname) - 4, fno.fname + ctx->cmdline_insertpos, strlen(fno.fname) - ctx->cmdline_insertpos - 4);
			fr = f_findnext(&dj, &fno);
		}
	}

	umm_free(search_term);
}

static void try_tab_expand_argument(struct tab_expansion_context *ctx)
{
	char *search_term = NULL;
	char *path = NULL;

	FRESULT fr;
	DIR dj;
	FILINFO fno;
	const char *searchTermStart;
	const char *lastSpace = strrchr(ctx->cmdline, ' ');
	const char *lastSlash = strrchr(ctx->cmdline, '/');

	if (lastSlash != NULL) {
		int pathLength = 1;

		if (lastSpace != NULL && lastSlash > lastSpace) {
			pathLength = lastSlash - lastSpace; // Path starts after the last space and includes the slash
		}
		if (lastSpace == NULL) {
			lastSpace = ctx->cmdline;
			pathLength = lastSlash - lastSpace;
		}

		path = (char *)umm_malloc(pathLength + 1);  // +1 for null terminator
		if (path == NULL) {
			return;
		}
		strncpy(path, lastSpace + 1, pathLength);   // Start after the last space
		path[pathLength] = '\0';		    // Null-terminate the string

		// Determine the start of the search term
		searchTermStart = lastSlash + 1;
		if (lastSpace != NULL && lastSpace > lastSlash) {
			searchTermStart = lastSpace + 1;
		}
		search_term = (char *)umm_malloc(strlen(searchTermStart) + 2); // +2 for '*' and null terminator
	} else {
		path = (char *)umm_malloc(1);
		if (path == NULL) {
			return;
		}
		path[0] = '\0';						       // Path is empty (current dir, essentially).

		searchTermStart = lastSpace ? lastSpace + 1 : ctx->cmdline;
		search_term = (char *)umm_malloc(strlen(searchTermStart) + 2); // +2 for '*' and null terminator
	}

	if (search_term == NULL) {
		if (path) umm_free(path);
		return;
	}

	strcpy(search_term, lastSpace && lastSlash > lastSpace ? lastSlash + 1 : lastSpace ? lastSpace + 1
											   : ctx->cmdline);
	strcat(search_term, "*");

	// printf("Path:\"%s\" Pattern:\"%s\"\r\n", path, search_term);
	fr = f_findfirst(&dj, &fno, path, search_term);

	while (fr == FR_OK && fno.fname[0]) {
		// unsafe
		char expansion[128];
		expansion[0] = 0;
		strncat(expansion, fno.fname + strlen(search_term) - 1, sizeof(expansion) - 2);
		if (fno.fattrib & AM_DIR) strcat(expansion, "/");
		tab_expansion_callback(ctx, fno.fattrib & AM_DIR ? ExpandDirectory : ExpandNormal, fno.fname, strlen(fno.fname), expansion, strlen(expansion));
		fr = f_findnext(&dj, &fno);
	}

	// Free the allocated memory
	if (search_term) umm_free(search_term);
	if (path) umm_free(path);
}

static void do_tab_complete(char *buffer, int *out_InsertPos, int *out_buflen)
{
	struct tab_expansion_context tab_ctx = {
		.num_matches = 0,
		.cmdline = buffer,
		.cmdline_insertpos = *out_InsertPos,
		.expansion = "\0"
	};

	const int BUFFER_LEN = 256; // TODO make dynamic

	bool got_spaces_before_insertpos = false;
	for (int i = 0; i < *out_InsertPos; i++) {
		if (buffer[i] == ' ') {
			got_spaces_before_insertpos = true;
			break;
		}
	}

	if (!got_spaces_before_insertpos) {
		try_tab_expand_internal_cmd(&tab_ctx);
		try_tab_expand_bin_name(&tab_ctx);
	} else {
		try_tab_expand_argument(&tab_ctx);
	}

	const int num_chars_added = strlen(tab_ctx.expansion);
	if (tab_ctx.num_matches > 0 && tab_complete_state == TabCompleteShowOptions) {
		printf("\n");
	}
	if (tab_complete_state < TabCompleteShowOptions) {
		tab_complete_state++;
	}
	bool do_full_redraw = false;
	if (num_chars_added > 0) {
		if (tab_ctx.num_matches == 1 && tab_ctx.expansion[num_chars_added - 1] != '/') {
			strncat(tab_ctx.expansion, " ", sizeof(tab_ctx.expansion) - strlen(tab_ctx.expansion) - 1);
		}
		const bool append_at_eol = (*out_InsertPos) == strlen(buffer);
		strinsert(buffer, tab_ctx.expansion, *out_InsertPos, BUFFER_LEN);
		if (append_at_eol) {
			printf("%s", tab_ctx.expansion);
			*out_InsertPos = strlen(buffer);
		} else {
			*out_InsertPos = (*out_InsertPos) + strlen(tab_ctx.expansion);
			do_full_redraw = true;
		}
		*out_buflen = strlen(buffer);
		return;
	} else if (tab_complete_state == TabCompleteShowOptions) {
		do_full_redraw = true;
	}
	if (do_full_redraw) {
		putch('\r');
		mos_print_prompt();
		printf("%s", buffer);
		uint8_t insert_pos_adjust = strlen(buffer) - (*out_InsertPos);
		while (insert_pos_adjust--) {
			doLeftCursor();
		}
	}
}

// The main line edit function
// Parameters:
// - buffer: Pointer to the line edit buffer
// - bufferLength: Size of the buffer in bytes
// - flags: Set bit0 to 0 to not clear, 1 to clear on entry
// Returns:
// - The exit key pressed (ESC or CR)
//
uint24_t mos_EDITLINE(char *buffer, int bufferLength, uint8_t flags)
{
	bool clear = flags & 0x01;		// Clear the buffer on entry
	bool enableTab = flags & 0x02;		// Enable tab completion (default off)
	bool enableHotkeys = !(flags & 0x04);	// Enable hotkeys (default on)
	bool enableHistory = !(flags & 0x08);	// Enable history (default on)
	uint8_t keya = 0;			// The ASCII key
	uint8_t keyr = 0;			// The ASCII key to return back to the calling program

	tab_complete_state = TabCompleteInitial;
	int limit = bufferLength - 1;		// Max # of characters that can be entered
	int insertPos;				// The insert position
	int len = 0;				// Length of current input
	history_no = history_size;		// Ensure our current "history" is the end of the list

	active_console->get_mode_information(); // Get the current screen dimensions

	if (clear) {				// Clear the buffer as required
		// memset(buffer, 0, bufferLength);
		buffer[0] = 0;
		insertPos = 0;
	} else {
		printf("%s", buffer);	    // Otherwise output the current buffer
		insertPos = strlen(buffer); // And set the insertpos to the end
	}

	// Loop until an exit key is pressed
	//
	while (keyr == 0) {
		struct keyboard_event_t ev;
		uint8_t historyAction = 0;
		len = strlen(buffer);
		kbuf_wait_keydown(&ev);
		keya = ev.ascii;

		if (keya != '\t') {
			tab_complete_state = TabCompleteInitial;
		}

		switch (ev.vkey) {
		//
		// First any extended (non-ASCII keys)
		//
		case 0x85: { // HOME
			insertPos = gotoEditLineStart(insertPos);
		} break;
		case 0x87: { // END
			insertPos = gotoEditLineEnd(insertPos, len);
		} break;

		case 0x92: { // PgUp
			historyAction = 2;
		} break;

		case 0x94: { // PgDn
			historyAction = 3;
		} break;

		case 0x9F:   // F1
		case 0xA0:   // F2
		case 0xA1:   // F3
		case 0xA2:   // F4
		case 0xA3:   // F5
		case 0xA4:   // F6
		case 0xA5:   // F7
		case 0xA6:   // F8
		case 0xA7:   // F9
		case 0xA8:   // F10
		case 0xA9:   // F11
		case 0xAA:   // F12
		{
			uint8_t fkey = ev.vkey - 0x9F;
			if (enableHotkeys && handleHotkey(fkey, buffer, bufferLength, insertPos, len)) {
				len = strlen(buffer);
				insertPos = len;
				keya = 0x0D;
				// Key was present, so drop through to ASCII key handling
			} else
				break; // key wasn't present, so do nothing
		}

		//
		// Now the ASCII keys
		//
		default:
			if (keya == 0)
				break;
			if (keya >= 0x20 && keya != 0x7F) {
				if (insertCharacter(buffer, keya, insertPos, len, limit)) {
					insertPos++;
				}
			} else {
				switch (keya) {
				case 0x1:		   // CTRL-A
					insertPos = gotoEditLineStart(insertPos);
					break;
				case 0x5:		   // CTRL-E
					insertPos = gotoEditLineEnd(insertPos, len);
					break;
				case 0x08:		   // Cursor Left
					if (insertPos > 0) {
						doLeftCursor();
						insertPos--;
					}
					break;
				case 0x09:		   // Tab
					if (enableTab) {
						do_tab_complete(buffer, &insertPos, &len);
					}
					break;
				case 0x0A:		   // Cursor Down
					historyAction = 3;
					break;
				case 0x0B:		   // Cursor Up
					historyAction = 2;
					break;
				case 0x0D:		   // Enter
					historyAction = 1;
					keyr = keya;
					break;
				case 0x0E:		   // CTRL-N
					historyAction = 3; // Next history item
					break;
				case 0x10:		   // CTRL-P
					historyAction = 2; // Previous history item
					break;
				case 0x15:		   // Cursor Right
					if (insertPos < len) {
						doRightCursor();
						insertPos++;
					}
					break;
				case 0x17:		   // CTRL-W
					// Delete last word
					insertPos -= deleteWord(buffer, insertPos, len);
					break;
				case 0x1B: // Escape
					keyr = keya;
					break;
				case 0x7F: // Backspace
					if (deleteCharacter(buffer, insertPos, len)) {
						insertPos--;
					}
					break;
				}
			}
		}

		if (enableHistory) {
			bool lineChanged = false;
			switch (historyAction) {
			case 1:				    // Push new item to stack
				editHistoryPush(buffer);
				break;
			case 2:				    // Move up in history
				lineChanged = editHistoryUp(buffer, insertPos, len, limit);
				break;
			case 3:				    // Move down in history
				lineChanged = editHistoryDown(buffer, insertPos, len, limit);
				break;
			}

			if (lineChanged) {
				printf("%s", buffer);	    // Output the buffer
				insertPos = strlen(buffer); // Set cursor to end of string
				len = strlen(buffer);
			}
		}
	}
	len -= insertPos;				    // Now just need to cursor to end of line; get # of characters to cursor

	while (len >= scrcols) {			    // First cursor down if possible
		putch(0x0A);
		len -= scrcols;
	}
	while (len-- > 0)
		putch(0x09);				    // Then cursor right for the remainder

	return keyr;					    // Finally return the keycode
}

void editHistoryInit()
{
	int i;
	history_no = 0;
	history_size = 0;

	for (i = 0; i < cmd_historyDepth; i++) {
		cmd_history[i] = NULL;
	}
}

void editHistoryPush(char *buffer)
{
	int len = strlen(buffer);

	if (len > 0) { // If there is data in the buffer
		char *newEntry = NULL;

		// if the new entry is the same as the last entry, then don't save it
		if (history_size > 0 && strcmp(buffer, cmd_history[history_size - 1]) == 0) {
			return;
		}

		newEntry = umm_malloc(len + 1);
		if (newEntry == NULL) {
			// Memory allocation failed so we can't save history
			return;
		}
		strcpy(newEntry, buffer);

		// If we're at the end of the history, then we need to shift all our entries up by one
		if (history_size == cmd_historyDepth) {
			int i;
			umm_free(cmd_history[0]);
			for (i = 1; i < history_size; i++) {
				cmd_history[i - 1] = cmd_history[i];
			}
			history_size--;
		}
		cmd_history[history_size++] = newEntry;
	}
}

bool editHistoryUp(char *buffer, int insertPos, int len, int limit)
{
	int index = -1;
	if (history_no > 0) {
		index = history_no - 1;
	} else if (history_size > 0) {
		// we're at the top of our history list
		// replace current line (which may have been edited) with first entry
		index = 0;
	}
	return editHistorySet(buffer, insertPos, len, limit, index);
}

bool editHistoryDown(char *buffer, int insertPos, int len, int limit)
{
	if (history_no < history_size) {
		if (history_no == history_size - 1) {
			// already at most recent entry - just leave an empty line
			removeEditLine(buffer, insertPos, len);
			history_no = history_size;
			return true;
		}
		return editHistorySet(buffer, insertPos, len, limit, ++history_no);
	}
	return false;
}

bool editHistorySet(char *buffer, int insertPos, int len, int limit, int index)
{
	if (index >= 0 && index < history_size) {
		removeEditLine(buffer, insertPos, len);
		if (strlen(cmd_history[index]) > limit) {
			// if the history entry is longer than the buffer, then we need to truncate it
			strncpy(buffer, cmd_history[index], limit);
			buffer[limit] = '\0';
		} else {
			strcpy(buffer, cmd_history[index]); // Copy from the history to the buffer
		}
		history_no = index;
		return true;
	}
	return false;
}
