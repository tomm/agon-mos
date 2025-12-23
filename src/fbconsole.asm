		.assume adl=1
		.global _start_fbterm
		.global _stop_fbterm
		.global _fbterm_width
		.global _fbterm_height
		.global _fbterm_fg
		.global _fbterm_bg
		.global _fb_curs_x
		.global _fb_curs_y
		.global _fb_mode
		.global _fb_lookupmode
		.global _fb_driverversion
		.global _fb_base
		.global _fbconsole_rst10_handler
		.global _fb_vdp_palette

FONT_WIDTH: .equ 4
FONT_HEIGHT: .equ 6

		.bss

_fb_mode:	.db 255 ; GPIO video disabled initially
_fbterm_width:
term_width:	.ds 1
_fbterm_height:
term_height:	.ds 1
_fbterm_fg:	.ds 1
_fbterm_bg:	.ds 1
_fb_curs_x:	.ds 1
_fb_curs_y:		.ds 1
fb_curs_ptr:	.ds 3 	; pointer into screen memory of current cursor loc
vdp_active_fn:	.ds 3
vdp_fn_args:	.ds 1
fbterm_flags:	.ds 1
_fb_base: 	.ds 3
cursor_mutex:	.db 1	; 1 when free, 0 when held

FLAG_IS_CURSOR_VIS: .equ 1
FLAG_DELAYED_SCROLL: .equ 2
FLAG_LOGO_DISMISSED: .equ 4

is_cursor_vis:	.ds 1

		.text

pre_image_callback:
		push af
		push bc
		push de
		push hl

		; If cursor was temporarily hidden this frame (ie when drawing text)
		; show it again before screen is exposed.
		; Try to take cursor mutex
		ld hl,cursor_mutex
		srl (hl)
		jr nc,2f		; nope. someone else holds it

		ld a,(fbterm_flags)
		and FLAG_IS_CURSOR_VIS
		or a
		jr nz,1f
		call show_cursor
	1:
		; release cursor_mutex
		ld hl,cursor_mutex
		inc (hl)

		ld a,(fbterm_flags)
		and FLAG_LOGO_DISMISSED
		jr nz,2f

		call draw_trippy_logo
	2:
		pop hl
		pop de
		pop bc
		pop af

		; Jump to vblank handler
		jp __2nd_jump_table + 100

_stop_fbterm:
		ld a,4		; api_videostop
		rst.lil 0x20
		ld a,255
		ld (_fb_mode),a
		ret

; returns zero on success, non-zero on error
_start_fbterm:
		push ix
		ld ix,0
		add ix,sp

		; is the driver present?
		call _fb_driverversion
		or a
		jp z,.no_driver

		; get videosetup
		ld a,2
		rst.lil 0x20

		; move framebuffer to desired location
		ld hl,(ix+9)	; _fb_base
		ld (_fb_base),hl
		ld (fb_curs_ptr),hl
		ld (iy+1),hl
		ld hl,(ix+12)	; fb_scanline_offsets
		ld (iy+4),hl
		ld hl,pre_image_callback
		ld (iy+7),hl

		; set mode
		ld a,1
		ld l,(ix+6)
		rst.lil 0x20

		; Init cursor mutex
		ld hl,cursor_mutex
		ld (hl),1

		; clear screen
		call fb_cls

		call term_init

		; Hook fbconsole to rst10
		call _console_enable_fb

		; Clear key event count to enable dismissing logo animation
		xor a
		ld (_keycount),a

		call do_splashmsg
		call always_draw_trippy_logo

		ld a,(ix+6)
		ld (_fb_mode),a

		pop ix
		ld hl,0
		ret

	.no_driver:
		pop ix
		ld hl,2
		ret

_fbconsole_rst10_handler:
		push af
		push bc
		push de
		push hl
		push ix
		push iy

		; Try to take cursor mutex
		ld hl,cursor_mutex
	1:	srl (hl)
		jr nc,1b		; nope. someone else holds it

		call hide_cursor

		call term_putch

		; Release cursor mutex
		ld hl,cursor_mutex
		inc (hl)

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
		ld (_fbterm_bg),a
		ld a,255
		ld (_fbterm_fg),a

		ld hl,_interpret_char
		ld (vdp_active_fn),hl

		pop iy
		ret

term_putch:	; character in `a`
		ld hl,(vdp_active_fn)
		jp (hl)

	.balign 0x10
_fb_vdp_palette:
		db 0, 0b1100000, 0b1100, 0b1101100, 0b1, 0b1100001, 0b1101, 0b1101101
		db 0b100110, 0b11100000, 0b11100, 0b11111100, 0b11, 0b11100011, 0b11111, 0b11111111

_vdp_fn_gotoxy_arg0:
		ld (vdp_fn_args),a
		ld hl,_vdp_fn_gotoxy_arg1
		ld (vdp_active_fn),hl
		ret

_vdp_fn_gotoxy_arg1:
		ld hl,term_height
		cp (hl)
		jr nc,1f
		ld (_fb_curs_y),a
	1:
		dec hl ; hl=term_width
		ld a,(vdp_fn_args)
		cp (hl)
		jr nc,2f
		ld (_fb_curs_x),a
	2:
		call update_curs_ptr
		ld hl,_interpret_char
		ld (vdp_active_fn),hl
		ret

_vdp_fn_set_color:
		push de

		ld hl,_fbterm_fg
		bit 7,a
		jr z,1f
		ld hl,_fbterm_bg
		res 7,a
	1:
		and 15 	; clamp to 16-color agon palette
		ld de,_fb_vdp_palette
		add a,e
		ld e,a
		ld a,(de)
		ld (hl),a
		
		ld hl,_interpret_char
		ld (vdp_active_fn),hl
		pop de
		ret

_vdp_fn_rawchar:
		push af
		call do_scroll_if_needed
		pop af
		call raw_draw_char
		call move_cursor_right
		ld hl,_interpret_char
		ld (vdp_active_fn),hl
		ret

_vdp_fn_1arg_nop:
		ld hl,_interpret_char
		ld (vdp_active_fn),hl
		ret

move_cursor_left:
		ld a,(_fb_curs_x)
		dec a
		jr c,.move_up
		ld (_fb_curs_x),a
		; fast update of cursor pointer
		ld hl,(fb_curs_ptr)
		dec hl
		dec hl
		dec hl
		dec hl
		ld (fb_curs_ptr),hl
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
		call update_curs_ptr
		ret
	.at_top:
		xor a
		ld (_fb_curs_x),a
		call update_curs_ptr
		ret

move_cursor_right:
		ld a,(term_width)
		ld e,a
		ld a,(_fb_curs_x)
		inc a
		ld (_fb_curs_x),a
		cp e
		jp z,1f
		; fast update of cursor pointer
		ld hl,(fb_curs_ptr)
		inc hl
		inc hl
		inc hl
		inc hl
		ld (fb_curs_ptr),hl
		ret
	1:
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
		call update_curs_ptr
		ret
	.scroll:
		call update_curs_ptr
		ld a,(fbterm_flags)
		or FLAG_DELAYED_SCROLL
		ld (fbterm_flags),a
		;call do_scroll
		ret

move_cursor_up:
		ld a,(_fb_curs_y)
		dec a
		ret c
		ld (_fb_curs_y),a
		call update_curs_ptr
		ret

_interpret_char:
		push ix
		push iy

		; handle special characters
		cp 127
		jp z,.handle_backspace
		cp 32
		jp nc,.normal_char
		cp 31
		jp z,.handle_gotoxy
		cp 30
		jp z,.handle_gohome
		cp 27
		jp z,.handle_rawchar
		cp 22
		jp z,.handle_vdu22_changemode
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
		; All other <32 chars: ignore
		jp .end

	.normal_char:
		; No control sequence. Just draw char
		push af
		call do_scroll_if_needed
		pop af
		call raw_draw_char
		call move_cursor_right
	.end:
		pop iy
		pop ix
		ret

	.handle_vdu22_changemode:
		; don't change mode. just CLS
		ld hl,_vdp_fn_1arg_nop
		ld (vdp_active_fn),hl
		jp .handle_cls

	.handle_rawchar:
		ld hl,_vdp_fn_rawchar
		ld (vdp_active_fn),hl
		jr .end

	.handle_curs_up:
		call clear_delayed_scroll
		call move_cursor_up
		jp .end

	.handle_curs_right:
		push af
		call do_scroll_if_needed
		pop af
		call move_cursor_right
		jp .end

	.handle_curs_left:
		call clear_delayed_scroll
		call move_cursor_left
		jp .end

	.handle_backspace:
		call clear_delayed_scroll
		call move_cursor_left
		ld a,' '
		call raw_draw_char
		jp .end

	.handle_lf:
		call move_cursor_down
		push af
		call do_scroll_if_needed
		pop af
		jp .end

	.handle_gohome:
		call clear_delayed_scroll
		xor a
		ld (_fb_curs_x),a
		ld (_fb_curs_y),a
		call update_curs_ptr
		jp .end

	.handle_gotoxy:
		call clear_delayed_scroll
		ld hl,_vdp_fn_gotoxy_arg0
		ld (vdp_active_fn),hl
		jp .end

	.handle_color:
		ld hl,_vdp_fn_set_color
		ld (vdp_active_fn),hl
		jp .end

	.handle_cr:
		call clear_delayed_scroll
		xor a
		ld (_fb_curs_x),a
		call update_curs_ptr
		jp .end

	.handle_cls:
		call clear_delayed_scroll
		call fb_cls
		xor a
		ld (_fbterm_bg),a
		dec a
		ld (_fbterm_fg),a
		jp .handle_gohome

	.handle_clg:
		call clear_delayed_scroll
		call fb_cls
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
		ld de,(_fb_base)
		add hl,de
		xor a
		ld (hl),a
		push hl
		pop de
		inc de
		dec bc
		ldir
		ret

clear_delayed_scroll:
		push af
		ld a,(fbterm_flags)
		and ~FLAG_DELAYED_SCROLL
		ld (fbterm_flags),a
		pop af
		ret

do_scroll_if_needed:
		ld a,(fbterm_flags)
		and FLAG_DELAYED_SCROLL
		ret z
		xor FLAG_DELAYED_SCROLL
		ld (fbterm_flags),a

		call do_scroll
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
		ld de,(_fb_base)
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
		; modeinfo to iy
		call fb_get_modeinfo
		ld hl,(fb_curs_ptr)
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
		ld a,(_fbterm_fg)
		ld d,a
		ld a,(_fbterm_bg)
		ld e,a
	.lineloop:
		ld c,(hl)
		inc hl

		rlc c
		ld a,e
		jr nc,1f
		ld a,d
	1:	ld (ix+0),a
		rlc c
		ld a,e
		jr nc,1f
		ld a,d
	1:	ld (ix+1),a
		rlc c
		ld a,e
		jr nc,1f
		ld a,d
	1:	ld (ix+2),a
		rlc c
		ld a,e
		jr nc,1f
		ld a,d
	1:	ld (ix+3),a

		push de
		ld de,(iy+6)
		add ix,de
		pop de
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

        	ld hl,(_fb_base)
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
		ld a,(fbterm_flags)
		and FLAG_IS_CURSOR_VIS
		or a
		jr nz,1f
	
		call toggle_cursor
	1:
		pop af
		ret

hide_cursor:
		push af
		ld a,(fbterm_flags)
		and FLAG_IS_CURSOR_VIS
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
		ld a,(fbterm_flags)
		xor FLAG_IS_CURSOR_VIS
		ld (fbterm_flags),a
		ld hl,(fb_curs_ptr)
		ld b,FONT_HEIGHT
	.yloop:
		push bc
		ld b,FONT_WIDTH
		push hl
	.xloop:
		ld a,(hl)
		xor 0x3
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

update_curs_ptr:
		call get_hl_ptr_cursor_pos
		ld (fb_curs_ptr),hl
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
		ld de,(_fb_base)
		add hl,de

		ret

_fb_driverversion:
		xor a
		rst.lil 0x20
		ret

_fb_lookupmode:
		push ix
		ld ix,0
		add ix,sp
		ld hl,(ix+6)	; mode number
		ld a,6		; api_lookupmode
		rst.lil 0x20
		pop ix
		ret

font_4x6:
		.include "font_4x6.inc"

do_splashmsg:
		ld hl,splashmsg_1
		ld bc,0
		xor a
		rst.lil 0x18
		ret

draw_trippy_logo:
		ld a,(_keycount)
		or a
		jr z,always_draw_trippy_logo
		; key pressed. dismiss logo animation
		ld a,(fbterm_flags)
		or FLAG_LOGO_DISMISSED
		ld (fbterm_flags),a
		ret
always_draw_trippy_logo:
	3:
		push ix
		push iy
		ld ix,0
		add ix,sp

		; 'random' logo color in (ix-2)
		ld a,r
		sla a
		push af

		call fb_get_modeinfo	; iy
		; splash logo
		ld de,(_fb_base)
		ld hl,logo
		ld b,LOGO_H
	1:	push bc
		ld b,LOGO_W
		push de
		inc (ix-2)
		ld a,r
		ld c,a
		sla c
	2:
		ld a,(hl)
		and c
		inc hl
		ld (de),a
		inc de
		dec b
		jr nz,2b

		pop de
		pop bc
		; next line (de += screen.width)
		push hl
		ld hl,(iy+6)  ; screen.width
		add hl,de
		ex de,hl
		pop hl
		djnz 1b

		pop af
		pop iy
		pop ix
		ret

splashmsg_1:	.ascii "\x1e"
		.ascii "     Agon Computer 512K\r\n\r\n"
		.asciz "     eZ80 GPIO Video\r\n\r\n\r\n"

LOGO_W .equ 16
LOGO_H .equ 24
logo:
		.incbin "logo_16x24.raw"
