; Copyright 1999-2015 Aske Simon Christensen.
;
; The code herein is free to use, in whole or in part,
; modified or as is, for any legal purpose.
;
; No warranties of any kind are given as to its behavior
; or suitability.


; Perhaps might be better to reimplement this from the C code:
;   DataFile.h: DataFile.verify uses
;	LZDecoder.h: LZDecoder.decode with
;   RangeDecoder.h: RangeDecoder as the Decoder.
;

.err This insrtuction for instruction port of 68000 code does not work!

; Main loop for decoding is in LZDecoder.decode.
; Uses decoder->decode (bit) and decoder->decodeNumber to implement LZ.
; class RangeDecoder implements decode using the contexts / probability scheme to decode individual bits.
; class Decoder implements decodeNumber to decode a number >=2 using a varibale-length encoding.
;
; Question: do we care enough to implement yet another decruncher?

.equ INIT_ONE_PROB, 0x8000
.equ ADJUST_SHIFT, 4
.equ SINGLE_BIT_CONTEXTS, 1
.equ NUM_CONTEXTS, 1536
.equ PARITY_CONTEXT, 1		; frees D7

; Decompress Shrinkler-compressed data produced with the --data option.
;
; A0 = Compressed data
; A1 = Decompressed data destination
; A2 = Progress callback, can be zero if no callback is desired.
;      Callback will be called continuously with
;      D0 = Number of bytes decompressed so far
;      A0 = Callback argument
; A3 = Callback argument
; D7 = 0 to disable parity context (Shrinkler --bytes / -b option)
;      1 to enable parity context (default Shrinkler compression)
;
; Uses 3 kilobytes of space on the stack.
; Preserves D2-D7/A2-A6 and assumes callback does the same.
;
; Decompression code may read one longword beyond compressed data.
; The contents of this longword does not matter.

; For ARM assume:
;                d0 => R0
;                d1 => R1
;                d2 => R2
;                d3 => R3
;                d4 => R4
;                d5 => R5
;                d6 => R6
;                d7 => (const)
;
;                a0 => R8
;				 a1 => R9
;				 a2 => (const)
;				 a3 => (const)
;				 a4 => R10	= pIn
;				 a5 => R11	= pOut
;				 a6 => (const)
;				 a7 => sp
;
; Note: d7 is constant, so can be assemble option.
;       a2, a3, a6, can be looked up during callback.
;
; 				 R7 => temp
;				R12 => bit
;
; ARM
; R0 = Compressed data
; R1 = Decompressed data destination
; R2 = Progress callback, can be zero if no callback is desired.
;      Callback will be called continuously with
;      D0 = Number of bytes decompressed so far
;      A0 = Callback argument
; R3 = Callback argument
;
ShrinklerDecompress:
	; Stash all regs for now.
	stmfd sp!, {r0-lr}				; movem.l	d2-d7/a4-a6,-(a7)

	; Free up R2, R3 for d2, d3
	str r2, progress_callback
	str r3, callback_argument

	; Free up R0, R1 for d0, d1
	mov r10, r0						; move.l	a0,a4
	mov r11, r1						; move.l	a1,a5
	str r1, decompress_base			; move.l	a1,a6

	; Init range decoder state
	mov r2, #0						; moveq.l	#0,d2
	mov r3, #1						; moveq.l	#1,d3
	mov r4, #1						; moveq.l	#1,d4
	movs r4, r4, ror #1				; ror.l		#1,d4

	; Init probabilities
	mov r6, #NUM_CONTEXTS			; move.l	#NUM_CONTEXTS,d6
	mov r7, #INIT_ONE_PROB			; temp.
init:
	str r7, [sp, #-4]!				; move.w	#INIT_ONE_PROB,-(a7)
	subs r6, r6, #1					; subq.w	#1,d6
	bne init						; bne.b	.init

	; D6 = 0

	; Urgh! In 68K C=prev_was_ref flag, X=decoded bit.

lit:
	; Literal
	add r6, r6, #1					; addq.b	#1,d6 [BYTE]
getlit:
	bl GetBit						; bsr.b		GetBit
	adc r6, r6, r6					; addx.b	d6,d6
	bcc getlit						; bcc.b		.getlit
	strb r6, [r11], #1				; move.b	d6,(a5)+
	bl ReportProgress				; bsr.b		ReportProgress
switch:
	; After literal
	bl GetKind						; bsr.b		GetKind
	bcc lit							; bcc.b		.lit
	; Reference
	mov r6, #-1						; moveq.l	#-1,d6
	bl GetBit						; bsr.b		GetBit
	bcc readoffset					; bcc.b		.readoffset
readlength:
	mov r6, #4						; moveq.l	#4,d6
	bl GetNumber					; bsr.b		GetNumber
copyloop:
	ldrb r7, [r11, r5]
	strb r7, [r11], #1				; move.b	(a5,d5.l),(a5)+
	subs r0, r0, #1					; subq.l	#1,d0
	bne copyloop					; bne.b		.copyloop
	bl ReportProgress				; bsr.b		ReportProgress
	; After reference
	bl GetKind						; bsr.b		GetKind
	bcc lit						; bcc.b		.lit
readoffset:
	mov r6, #3						; moveq.l	#3,d6
	bl GetNumber					; bsr.b		GetNumber
	mov r5, #2						; moveq.l	#2,d5
	subs r5, r5, r0					; sub.l		d0,d5
	bne readlength					; bne.b		.readlength

	mov r7, #NUM_CONTEXTS*2			; lea.l	NUM_CONTEXTS*2(a7),a7
	add sp, sp, r7, lsl #2			
	ldmfd sp!, {r0-lr}				; movem.l	(a7)+,d2-d7/a4-a6
	mov pc, lr						; rts

ReportProgress:
	str lr, [sp, #-4]!
	ldr r7, progress_callback		; temp
	cmp r7, #0
	beq .nocallback					; beq.b		.nocallback
	mov r0, r11						; move.l	a5,d0
	ldr r12, decompress_base
	sub r0, r0, r12					; sub.l		a6,d0
	ldr r1, callback_argument		; move.l	a3,a0
	mov pc, r7						; jsr		(a2)
.nocallback:
	ldr pc, [sp], #4				; rts

progress_callback:
	.long 0

callback_argument:
	.long 0

decompress_base:
	.long 0

GetKind:
	; Use parity as context
	mov r6, r11						; move.l	a5,d6
	and r6, r6, #PARITY_CONTEXT		; and.l		d7,d6
	mov r6, r6, lsl #8				; lsl.w		#8,d6
	b GetBit						; bra.b		GetBit

GetNumber:
	str lr, [sp, #-4]!
	; D6 = Number context

	; Out: Number in D0
	mov r6, r6, lsl #8				; lsl.w		#8,d6
numberloop:
	add r6, r6, #2					; addq.b	#2,d6
	bl GetBit						; bsr.b		GetBit
	bcs numberloop					; bcs.b		.numberloop
	mov r0, #1						; moveq.l	#1,d0
	sub r6, r6, #1					; subq.b	#1,d6
bitsloop:
	bl GetBit						; bsr.b		GetBit
	adc r0, r0, r0					; addx.l	d0,d0
	subs r6, r6, #2					; subq.b	#2,d6
	bcc bitsloop					; bcc.b	.bitsloop
	ldr pc, [sp], #4				; rts

	; D6 = Bit context

	; D2 = Range value
	; D3 = Interval size
	; D4 = Input bit buffer

	; Out: Bit in C and X

readbit:
	adds r4, r4, r4					; add.l		d4,d4
	bne nonewword					; bne.b		nonewword
	ldr r4, [r10], #4				; move.l	(a4)+,d4
	adc r4, r4, r4					; addx.l	d4,d4
	; LOSE CARRY HERE? -V
nonewword:
	adc r2, r2, r2					; addx.w	d2,d2
	add r3, r3, r3					; add.w		d3,d3
GetBit:
	tst r3, #0						; tst.w		d3
	bpl readbit						; bpl.b		readbit

	; lea.l	4+SINGLE_BIT_CONTEXTS*2(a7,d6.l),a1
	add r9, r6, r6					; add.l		d6,a1
	add r9, r9, #4+SINGLE_BIT_CONTEXTS*2
	; *2 for long words on ARM.
	ldr r1, [sp, r9, lsl #1]		; move.w	(a1),d1
	; D1 = One prob

	mov r1, r1, lsr #ADJUST_SHIFT	; lsr.w	#ADJUST_SHIFT,d1
	ldr r7, [sp, r9, lsl #1]
	sub r7, r7, r1
	str r7, [sp, r9, lsl #1]		; sub.w		d1,(a1)	; (a1)-=d1
	add r1, r1, r7					; add.w		(a1),d1	; d1+=(a1)

	mul r1, r3, r1					; mulu.w	d3,d1
	mov r1, r1, lsr #16				; swap.w	d1

	subs r2, r2, r1					; sub.w		d1,d2
	blo one						; blo.b		.one
zero:
	; oneprob = oneprob * (1 - adjust) = oneprob - oneprob * adjust
	subs r3, r3, r1					; sub.w	d1,d3
	; 0 in C [and X]
	mov pc, lr						; rts
one:
	; onebrob = 1 - (1 - oneprob) * (1 - adjust) = oneprob - oneprob * adjust + adjust
	ldr r7, [sp, r9, lsl #1]
	add r7, r7, #0xffff>>ADJUST_SHIFT
	str r7, [sp, r9, lsl #1]		; add.w		#$ffff>>ADJUST_SHIFT,(a1)
	mov r3, r1						; move.w	d1,d3
	adds r2, r2, r1					; add.w		d1,d2
	; 1 in C [and X]
	mov pc, lr						; rts
