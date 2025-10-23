		.assume	adl = 1	
		.text
		.global _kbuf_poll_event
		.global _kbuf_wait_keydown
		.global _kbuf_clear
		.global kbuf_append

_kbuf_wait_keydown:
		push ix
		ld ix,0
		add ix,sp
	.try:
		ld de,(ix+6)
		call kbuf_remove	
		jr z,.try

		; is it keydown?
		ld de,(ix+6)
		inc de
		inc de
		inc de
		ld a,(de)
		or a
		jr z,.try

		pop ix
		ret

_kbuf_poll_event:
		push ix
		ld ix,0
		add ix,sp
		ld de,(ix+6)
		call kbuf_remove	
		pop ix
		ld a,0
		jr nz,.success
		ret
	.success:
		inc a
		ret

kbuf_append:	; 4-byte value to append in (de). set `z` if no space
		; put (de)..(de+3) to kbbuf_data[kbbuf_end_idx*4]
		ld hl,0
		ld a,(kbbuf_end_idx)
		ld l,a
		add hl,hl
		add hl,hl
		ld bc,kbbuf_data
		add hl,bc

		ex de,hl
		ld bc,4
		ldir

		; c := (kbbuf_end_idx+1) & KBBUF_LEN
		ld a,(kbbuf_end_idx)
		inc a
		ld c,KBBUF_LEN
		and c
		ld c,a

		ld a,(kbbuf_start_idx)
		cp c

		; if kbbuf_start_idx==kbbuf_end_idx+1 then no space for appending
		ret z
		
		; otherwise write new kbbuf_end_idx
		ld a,c
		ld (kbbuf_end_idx),a
		ret

; Take 1 event from the keyboard buffer (store to (de) struct keyboard_event_t*)
kbuf_remove:	; remove 4-byte value into (de)..(de+3). `z` flag set if no bytes in fifo
		ld hl,0
		ld a,(kbbuf_start_idx)
		ld l,a
		ld a,(kbbuf_end_idx)
		cp l
		ret z

		add hl,hl
		add hl,hl
		ld bc,kbbuf_data
		add hl,bc
		ld bc,4
		ldir

		ld a,(kbbuf_start_idx)
		inc a
		and KBBUF_LEN
		ld (kbbuf_start_idx),a

		or a		; clear `z` flag
		ret

; Clear (flush) the keyboard buffer
_kbuf_clear:
		push hl
		ld hl,kbbuf_start_idx
		xor a
		; Clear buffer with interrupts disabled to make it atomic
		di
		ld (hl),a
		inc hl
		ld (hl),a
		ei
		pop hl
		ret

		.bss
KBBUF_LEN: 	.equ 31		; must be POT-1, and <256
kbbuf_start_idx:	db 0
kbbuf_end_idx: 		db 0
kbbuf_data:		ds (KBBUF_LEN+1)*4
