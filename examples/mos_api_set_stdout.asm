		.assume adl=1
		.org 0x40000
		jp start
		.align 0x40
		.db "MOS",0,1

mos_api_set_stdout: .equ 0x64

start:
		; Switch to VDP output
		ld a,mos_api_set_stdout
		ld c,0
		rst.lil 8

		ld hl,msg1
		ld bc,0
		xor a
		rst.lil 0x18

		; Switch to FB output
		ld a,mos_api_set_stdout
		ld c,2
		rst.lil 8

		ld hl,msg2
		ld bc,0
		xor a
		rst.lil 0x18
		
		ld hl,0
		ret
		
msg1:		.asciz "Hello VDP!\r\n"
msg2:		.asciz "Hello Framebuffer!\r\n"
