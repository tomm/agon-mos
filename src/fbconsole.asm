		.assume adl=1
		.global _start_fbterm
		.global _fbterm_width
		.global _fbterm_height
		.global _fb_curs_x
		.global _fb_curs_y

MODE:		.equ	2
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

		.text

; returns zero on success, non-zero on error
_start_fbterm:
		push ix
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
		ld l,MODE
		rst.lil 0x20

		; clear screen
		call fb_cls

		call term_init

		; hook into rst10. only works with agondev mos
		ld a,0x61
		ld e,0x10
		ld hl,rst10_handler
		rst.lil 8

		; get modeinfo
		ld a,3
		rst.lil 0x20

		; enable fb console (needs agondev mos)
		ld a,0x63 ; mos_api_startfbconsole
		ld hl,FB_BASE
		ld ix,MODE
		ld de,(iy+6)	; screen.width
		ld bc,(iy+9)	; screen.height
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
		call term_putch
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

		ld hl,_draw_char
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
		ld hl,_draw_char
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
		
		ld hl,_draw_char
		ld (vdp_active_fn),hl
		pop de
		ret

_draw_char:
		push ix
		push iy
		push af
			; rotate through colours
			;ld hl,term_fg
			;dec (hl)
			;jr nz,@f
			;dec (hl)
		;@@:
			; get modeinfo
			ld a,3
			rst.lil 0x20
		
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
		pop af

		; handle special characters
		cp 31
		jp z,.handle_gotoxy
		cp 30
		jp z,.handle_gohome
		cp 17
		jp z,.handle_color
		cp 13
		jp z,.handle_cr
		cp 12
		jp z,.handle_cls
		cp 10
		jp z,.handle_lf

		push hl
			; seek to character in font
			ld b,a
			ld c,6
			mlt bc
			ld hl,font_4x6
			add hl,bc

		; framebuffer char position in ix
		pop ix

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

		ld a,(term_width)
		ld e,a
		ld a,(_fb_curs_x)
		inc a
		ld (_fb_curs_x),a
		cp e
		jr nz,.end

	
		; go to next line
		xor a
		ld (_fb_curs_x),a

	.handle_lf:
		ld a,(term_height)
		ld e,a
		ld a,(_fb_curs_y)
		inc a
		cp e
		jr z,.handle_scroll
		ld (_fb_curs_y),a


	.end:
		pop iy
		pop ix
		ret

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

	.handle_scroll:
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

fb_cls:
		push iy
		; get modeinfo (iy)
		ld a,3
		rst.lil 0x20

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

font_4x6:
		.include "font_4x6.inc"
