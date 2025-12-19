		.assume adl=0
		.org $0
		jp start
		.align $40
		.db "MOS",0,0	; header version 0, Z80 mode
start:
		push.lil iy

	@loop:
		ld a,0x62		; mos_api_pollkeyboardevent
		ld de,eventbuf
		rst.lil 8

		and a
		jr z,@loop		; no event yet...

		ld a,(e_ascii)
		and a
		jr z,@loop		; ignore non-ascii keys

		ld a,(e_isdown)
		and a
		jr z,@isup

		ld hl,msg_dn
		ld bc,0
		xor a
		rst.lis 0x18

		ld a,(e_ascii)
		rst.lis 0x10

		jp @loop
	
	@isup:
		ld hl,msg_up
		ld bc,0
		xor a
		rst.lis 0x18

		ld a,(e_ascii)
		rst.lis 0x10

		jp @loop

	@end:
		ld.lil hl, 0
		pop.lil iy
		ret.lis

eventbuf:
e_ascii:	.db 0
e_kmod:		.db 0
e_vkey:		.db 0
e_isdown:	.db 0
msg_dn:
		.db " Key down: ", 0
msg_up:
		.db " Key up: ", 0
