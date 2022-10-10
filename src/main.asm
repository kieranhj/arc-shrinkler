; ============================================================================
; Shrinkler test harness.
; TODO: May become a Module at some point?
; ============================================================================

.equ _DEBUG, 1

.include "lib/swis.h.asm"

.org 0x8000

; ============================================================================
; Stack
; ============================================================================

Start:
    adrl sp, stack_base
	B main

.skip 1024
stack_base:

; ============================================================================
; Main
; ============================================================================

main:
	str lr, [sp, #-4]!
	; R0 = Compressed data
	; R1 = Decompressed data destination
	; R2 = Progress callback, can be zero if no callback is desired.
	;      Callback will be called continuously with
	;      D0 = Number of bytes decompressed so far
	;      A0 = Callback argument
	; R3 = Callback argument

	;adr r0, compressed_data
	;adr r1, decompressed_data
	;mov r2, #0
	;mov r3, #0
	;bl ShrinklerDecompress

	; Wipe decompressed area so we're not fooled!
	ldr r11, p_out
	mov r0, #0
	mov r1, #63336
	.1:
	str r0, [r11], #4
	subs r1, r1, #1
	bne .1

	adr r0, compressed_data
	ldr r1, p_out
	adr r2, write_bytes_callback
	mov r3, #0
	adr r9, context
	bl ShrinklerDecompress

	swi OS_WriteI+13
	swi OS_WriteI+10

	adr r1, string_buffer
	mov r2, #16
	swi OS_ConvertCardinal4

	adr r0, wrote_msg
	swi OS_WriteO
	adr r0, string_buffer
	swi OS_WriteO
	swi OS_WriteI+13
	swi OS_WriteI+10

	ldr pc, [sp], #4
	swi OS_Exit

string_buffer:
	.skip 16

wrote_msg:
	.byte "Wrote bytes:",0
	.align 4

write_bytes_callback:
	str r2, [sp, #-4]!
	mov r1, r0, lsr #12
	ldr r2, .1
	cmp r1, r2
	ldreq r2, [sp], #4
	moveq pc ,lr
	str r1, .1
	
	adr r1, string_buffer
	mov r2, #16
	swi OS_ConvertCardinal4
	swi OS_WriteI+13
	adr r0, string_buffer
	swi OS_WriteO
	swi OS_WriteI+32
	swi OS_WriteI+'b'
	swi OS_WriteI+'y'
	swi OS_WriteI+'t'
	swi OS_WriteI+'e'
	swi OS_WriteI+'s'
	ldr r2, [sp], #4
	mov pc ,lr
.1:
	.long -1

; ============================================================================
; Code
; ============================================================================

.include "arc-shrinkler.asm"

; ============================================================================
; Data
; ============================================================================

p_out:
	.long decompressed_data

context:
.skip NUM_CONTEXTS*4

compressed_data:
;.incbin "build/a252.shri"
;.incbin "build/stniccc.shri"
.incbin "build/waytoorude.shri"
.align 4

decompressed_data:
