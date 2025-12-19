	.assume adl=1
	jp start
	.align 0x40
	db "MOS",0,1

mos_api_set_fbmode: .equ 0x63

start:
	; mode -1 to return to VDP video
	; mode 0x100 to re-init fb console without changing mode
	ld bc,2		; mode number
	ld a,mos_api_set_fbmode
	rst.lil 8

	ld hl,0
	ret
