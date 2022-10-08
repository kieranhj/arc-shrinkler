; ============================================================================
; Shrinkler test harness.
; TODO: May become a Module at some point?
; ============================================================================

.equ _DEBUG, 0

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
	adr r11, decompressed_data
	mov r0, #0
	mov r1, #63336
	.1:
	str r0, [r11], #4
	subs r1, r1, #1
	bne .1

	adr r9, context
	adr r10, compressed_data
	adr r11, decompressed_data
	bl ShrinklerDecompress

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

; ============================================================================
; Code
; ============================================================================

.include "arc-shrinkler.asm"

; ============================================================================
; Data
; ============================================================================

context:
.skip NUM_CONTEXTS*4

compressed_data:
.incbin "build/test.shri"
.align 4

decompressed_data:
