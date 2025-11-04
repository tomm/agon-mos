		.assume adl=1
		.global _start_fbterm
		.global _fbterm_width
		.global _fbterm_height
		.global _fb_curs_x
		.global _fb_curs_y

FB_BASE: 	.equ	0xb1000		; only 4K left for moslets :)
FB_SCANLINE_OFFSETS: .equ 0xba240
FONT_WIDTH: .equ 4
FONT_HEIGHT: .equ 6

		.bss

_fbterm_width:
term_width:	.ds 1
_fbterm_height:
term_height:	.ds 1
term_fg:	.ds 1
term_bg:	.ds 1
_fb_curs_x:	.ds 1
_fb_curs_y:		.ds 1
vdp_active_fn:	.ds 3
vdp_fn_args:	.ds 1
is_cursor_vis:	.ds 1

		.text

; returns zero on success, non-zero on error
_start_fbterm:
		push ix
		ld ix,0
		add ix,sp

		; is the driver present?
		xor a
		rst.lil 0x20
		or a
		jp z,.no_driver

		; get videosetup
		ld a,2
		rst.lil 0x20

		; move framebuffer to desired location
		ld hl,FB_BASE
		ld (iy+1),hl
		ld hl,FB_SCANLINE_OFFSETS
		ld (iy+4),hl

		; set mode
		ld a,1
		ld l,(ix+6)
		rst.lil 0x20

		; clear screen
		call fb_cls

		call term_init

		; hook into rst10. only works with agondev mos
		ld a,0x61
		ld e,0x10
		ld hl,rst10_handler
		rst.lil 8

		pop ix
		ld hl,0
		ret

	.no_driver:
		pop ix
		ld hl,2
		ret

rst10_handler:
		push af
		push bc
		push de
		push hl
		push ix
		push iy
		call hide_cursor
		call term_putch
		call show_cursor
		pop iy
		pop ix
		pop hl
		pop de
		pop bc
		pop af
		ret.lil


term_init:	; size the terminal. needed after mode change
		push iy
		ld a,3
		rst.lil 0x20

		ld hl,(iy+6)	; screen.width
		ld de, FONT_WIDTH
		call udiv24
		ld a,e
		ld (term_width),a

		ld hl,(iy+9)	; screen.height
		ld de, FONT_HEIGHT
		call udiv24
		ld a,e
		ld (term_height),a

		xor a
		ld (_fb_curs_x),a
		ld (_fb_curs_y),a
		ld (term_bg),a
		ld a,255
		ld (term_fg),a

		ld hl,_interpret_char
		ld (vdp_active_fn),hl

		pop iy
		ret

term_putch:	; character in `a`
		ld hl,(vdp_active_fn)
		jp (hl)

	.balign 0x10
vdp_palette:
		db 0, 0b1100000, 0b1100, 0b1101100, 0b1, 0b1100001, 0b1101, 0b1101101
		db 0b100110, 0b11100000, 0b11100, 0b11111100, 0b11, 0b11100011, 0b11111, 0b11111111

_vdp_fn_gotoxy_arg0:
		ld (vdp_fn_args),a
		ld hl,_vdp_fn_gotoxy_arg1
		ld (vdp_active_fn),hl
		ret

_vdp_fn_gotoxy_arg1:
		ld (_fb_curs_y),a
		ld a,(vdp_fn_args)
		ld (_fb_curs_x),a
		ld hl,_interpret_char
		ld (vdp_active_fn),hl
		ret

_vdp_fn_set_color:
		push de
		ld hl,term_fg

		cp 16
		jr nc,1f

		; For colors <= 15, use the VDP palette (otherwise treat as rgb332)
		ld de,vdp_palette
		add a,e
		ld e,a
		ld a,(de)
	1:
		ld (hl),a
		
		ld hl,_interpret_char
		ld (vdp_active_fn),hl
		pop de
		ret

_vdp_fn_rawchar:
		call raw_draw_char
		call move_cursor_right
		ld hl,_interpret_char
		ld (vdp_active_fn),hl
		ret

move_cursor_left:
		ld a,(_fb_curs_x)
		dec a
		jr c,.move_up
		ld (_fb_curs_x),a
		ret
	.move_up:
		ld a,(_fb_curs_y)
		or a
		jr z,.at_top
		dec a
		ld (_fb_curs_y),a
		ld a,(term_width)
		dec a
		ld (_fb_curs_x),a
		ret
	.at_top:
		xor a
		ld (_fb_curs_x),a
		ret

move_cursor_right:
		ld a,(term_width)
		ld e,a
		ld a,(_fb_curs_x)
		inc a
		ld (_fb_curs_x),a
		cp e
		ret nz
		; go to next line
		xor a
		ld (_fb_curs_x),a
		call move_cursor_down
		ret

move_cursor_down:
		ld a,(term_height)
		ld e,a
		ld a,(_fb_curs_y)
		inc a
		cp e
		jr z,.scroll
		ld (_fb_curs_y),a
		ret
	.scroll:
		call do_scroll
		ret

move_cursor_up:
		ld a,(_fb_curs_y)
		dec a
		ret c
		ld (_fb_curs_y),a
		ret

_interpret_char:
		push ix
		push iy

		; handle special characters
		cp 127
		jp z,.handle_backspace
		cp 31
		jp z,.handle_gotoxy
		cp 30
		jp z,.handle_gohome
		cp 27
		jp z,.handle_rawchar
		cp 17
		jp z,.handle_color
		cp 16
		jp z,.handle_clg
		cp 13
		jp z,.handle_cr
		cp 12
		jp z,.handle_cls
		cp 11
		jp z,.handle_curs_up
		cp 10
		jp z,.handle_lf
		cp 9
		jp z,.handle_curs_right
		cp 8
		jp z,.handle_curs_left

		call raw_draw_char
		call move_cursor_right
	.end:
		pop iy
		pop ix
		ret

	.handle_rawchar:
		ld hl,_vdp_fn_rawchar
		ld (vdp_active_fn),hl
		jr .end

	.handle_curs_up:
		call move_cursor_up
		jp .end

	.handle_curs_right:
		call move_cursor_right
		jp .end

	.handle_curs_left:
		call move_cursor_left
		jp .end

	.handle_backspace:
		call move_cursor_left
		ld a,' '
		call raw_draw_char
		jp .end

	.handle_lf:
		call move_cursor_down
		jp .end

	.handle_gohome:
		xor a
		ld (_fb_curs_x),a
		ld (_fb_curs_y),a
		jr .end

	.handle_gotoxy:
		ld hl,_vdp_fn_gotoxy_arg0
		ld (vdp_active_fn),hl
		jr .end

	.handle_color:
		ld hl,_vdp_fn_set_color
		ld (vdp_active_fn),hl
		jr .end

	.handle_cr:
		xor a
		ld (_fb_curs_x),a
		jr .end

	.handle_cls:
		call fb_cls
		jp .handle_gohome

	.handle_clg:
		call fb_cls
		jp .end

	.handle_scroll:
		call do_scroll
		jp .end

	.clear_line:	; terminal line in de
		; number of bytes to wipe in bc
		ld hl,(iy+6)	; screen.width
		push de
		add hl,hl	; FONT_HEIGHT is 6
		push hl
		pop de
		add hl,hl
		add hl,de	; hl=screen.width*6
		push hl
		pop bc
		
		; find character y position
		ld hl,(iy+6)	; screen.width
		add hl,hl	; FONT_HEIGHT is 6
		push hl
		pop de
		add hl,hl
		add hl,de	; hl=screen.width*6
		pop de
		call umul24	; hl=screen.width*8*line_no
		ld de,FB_BASE
		add hl,de
		xor a
		ld (hl),a
		push hl
		pop de
		inc de
		dec bc
		ldir
		ret

do_scroll:
		call fb_get_modeinfo
		; bc = screen.width * (screen.height-6)
		ld hl,(iy+6)	; screen.width
		ld de,(iy+9)	; screen.height
		dec de
		dec de
		dec de
		dec de
		dec de
		dec de
		call umul24
		push hl
		pop bc

		ld hl,(iy+6)	; screen.width
		add hl,hl	; FONT_HEIGHT is 6
		push hl
		pop de
		add hl,hl
		add hl,de	; hl=screen.width*6
		ld de,FB_BASE
		add hl,de

		ldir
		
		ld de,0
		ld a,(term_height)
		dec a
		ld e,a
		call .clear_line

; Input:
;   a: character to draw
; Note:
;   This function performs no alteration of cursor position, text
;   color, or any other higher level terminal stuff. It just draws
;   the character.
raw_draw_char:
		push af
		; ptr to hl, modeinfo to iy
		call get_hl_ptr_cursor_pos
		push hl
		pop ix
		pop af
		; seek to character in font
		ld b,a
		ld c,6
		mlt bc
		ld hl,font_4x6
		add hl,bc
		; draw it
		ld b,FONT_HEIGHT
	.lineloop:
		ld c,(hl)
		inc hl

		rlc c
		ld a,(term_bg)
		jr nc,1f
		ld a,(term_fg)
	1:	ld (ix+0),a
		rlc c
		ld a,(term_bg)
		jr nc,1f
		ld a,(term_fg)
	1:	ld (ix+1),a
		rlc c
		ld a,(term_bg)
		jr nc,1f
		ld a,(term_fg)
	1:	ld (ix+2),a
		rlc c
		ld a,(term_bg)
		jr nc,1f
		ld a,(term_fg)
	1:	ld (ix+3),a

		ld de,(iy+6)
		add ix,de
		djnz .lineloop

		ret

fb_cls:
		push iy
		call fb_get_modeinfo	; iy

		; total screen bytes (minus 1) in bc
		ld hl,(iy+6)
		ld de,(iy+9)
		call umul24
		dec hl
		push hl
		pop bc

        	ld hl,FB_BASE
		push hl
		pop de
		inc de
		xor a
		ld (hl),a
		ldir
		pop iy
		ret

show_cursor:
		push af
		ld a,(is_cursor_vis)
		or a
		jr nz,1f
	
		call toggle_cursor
	1:
		pop af
		ret

hide_cursor:
		push af
		ld a,(is_cursor_vis)
		or a
		jr z,1f
	
		call toggle_cursor
	1:
		pop af
		ret

toggle_cursor:
		push iy
		; get modeinfo (iy)
		call fb_get_modeinfo

		ld a,(is_cursor_vis)
		xor 1
		ld (is_cursor_vis),a

		call get_hl_ptr_cursor_pos

		ld b,FONT_HEIGHT
	.yloop:
		push bc
		ld b,FONT_WIDTH
		push hl
	.xloop:
		ld a,(hl)
		xor 0xff
		ld (hl),a
		inc hl
		djnz .xloop
		pop hl
		pop bc
		ld de,(iy+6)	; screen.width
		add hl,de
		djnz .yloop
	
		pop iy
		ret

fb_get_modeinfo:	; to iy
		push af
		ld a,3
		rst.lil 0x20
		pop af
		ret

get_hl_ptr_cursor_pos:
		call fb_get_modeinfo	; iy
	
		; find character y position
		ld hl,(iy+6)	; screen.width
		add hl,hl	; FONT_HEIGHT is 6
		push hl
		pop de
		add hl,hl
		add hl,de	; hl=screen.width*6

		; hl=screen.width*8*_fb_curs_y
		ld de,0
		ld a,(_fb_curs_y)
		ld e,a
		call umul24

		; seek x character pos in framebuffer
		ld a,(_fb_curs_x)
		ld b,a
		ld c,FONT_WIDTH
		mlt bc
		add hl,bc

		; add base framebuffer address
		ld de,FB_BASE
		add hl,de

		ret

font_4x6:
		.include "font_4x6.inc"
