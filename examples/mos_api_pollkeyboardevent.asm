		.assume adl=1
		.org $40000
		jp start
		.align $40

		.db "MOS"
		.db 0 ; version
		.db 1 ; ADL enabled (24-bit addressing)
start:
		push iy

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
		rst.lil 0x18

		ld a,(e_ascii)
		rst.lil 0x10

		jp @loop
	
	@isup:
		ld hl,msg_up
		ld bc,0
		xor a
		rst.lil 0x18

		ld a,(e_ascii)
		rst.lil 0x10

		jp @loop

		ld hl, 0
		pop iy
		ret

eventbuf:
e_ascii:	.db 0
e_kmod:		.db 0
e_vkey:		.db 0
e_isdown:	.db 0
msg_dn:
		.db " Key down: ", 0
msg_up:
		.db " Key up: ", 0
