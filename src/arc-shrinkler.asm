; Copyright 1999-2015 Aske Simon Christensen.
;
; The code herein is free to use, in whole or in part,
; modified or as is, for any legal purpose.
;
; No warranties of any kind are given as to its behavior
; or suitability.

; ============================================================================
; Acorn Archimedes ARM Port of ShrinklerDecompress.S.
; 2022 Kieran Connell.
; ============================================================================

.equ INIT_ONE_PROB, 0x8000
.equ ADJUST_SHIFT, 4
.equ SINGLE_BIT_CONTEXTS, 1
.equ NUM_CONTEXTS, 1536
.equ PARITY_MASK, 1

.equ NUM_SINGLE_CONTEXTS, 1

.equ CONTEXT_KIND, 0
.equ CONTEXT_REPEATED, -1
.equ CONTEXT_GROUP_LIT, 0
.equ CONTEXT_GROUP_OFFSET, 2
.equ CONTEXT_GROUP_LENGTH, 3

; ============================================================================
; ARM Register Usage.
; ============================================================================

; R0  = temp / parameter / return value
; R1  = bool ref                (LZDecode)
; R2  = unsigned intervalvalue 	(RangeDecoder)
; R3  = unsigned intervalsize	(RangeDecoder)
; R4  = unsigned uncertainty    (RangeDecoder)
; R5  = bool prev_was_ref       (LZDecode)
; R6  = temp
; R7  = temp
; R8  = int offset              (LZDecode)
; R9  = context				    (global)
; R10 = source				    (global)
; R11 = dest				    (global)
; R12 = bit_buffer			    (global)

; ============================================================================
; Implements RangeDecoder::getBit().
; Returns R0 = bit.
; ============================================================================
GetBit:
    movs r12, r12, lsl #1       ; bit_buffer=bit_buffer << 1, C=top bit.
    bne .1                      ; if bit_buffer!=0 goto nonewword
    ldr r12, [r10], #4          ; bit_buffer = *pCompressed++ [3210]
    ; Argh! Endian swap word for ARM.
    ; TODO: Add this as an additional option to Shrinkler compressor.
    mov r0, r12, lsr #24        ; [xxx3]
    orr r0, r0, r12, lsl #24    ; [0xx3]
    and r1, r12, #0x00ff0000
    orr r0, r0, r1, lsr #8      ; [0x23]
    and r1, r12, #0x0000ff00
    orr r12, r0, r1, lsl #8     ; [0123]
    ;
    adcs r12, r12, r12          ; bit_buffer=(bit_buffer << 1) | C
.1:                             ; nonewword:
    movcc r0, #0                ; bit = C
    movcs r0, #1                ; bit = C
    mov pc, lr                  ; return bit

; ============================================================================
; Implements RangeDecoder::decode(int context_index).
; Decode a bit in the given context.
; Returns the decoded bit value.
; R0 = context_index
; Returns R0 = bit
; ============================================================================
RangeDecodeBit:
	stmfd sp!, {r1, r5, r7, lr}	; <= REGISTER PRESSURE!

	.if _DEBUG
	cmp r0, #0					; assert(context_index < contexts.size());
	bmi .4
	cmp r0, #NUM_CONTEXTS		; assert(context_index < contexts.size());
	blt .3
	.4:
	adr r0, assert1
	swi OS_GenerateError
	.3:
	.endif

	str r0, [sp, #-4]!			; <= REGISTER PRESSURE!
.1:
	cmp r3, #0x8000				; while (intervalsize < 0x8000) {
	bge .2
	mov r3, r3, lsl #1			; 	intervalsize <<= 1;
	bl GetBit					; 	r0=GetBit()
	orr r2, r0, r2, lsl #1		; 	intervalvalue = (intervalvalue << 1) | getBit();
	b .1						; }
.2:
	ldr r0, [sp], #4			; <= REGISTER PRESSURE!
	ldr r1, [r9, r0, lsl #2]	; unsigned prob = contexts[context_index];

	; R0 =	int bit;
	; R7 =	unsigned new_prob;
	; R8 =	unsigned threshold
	mul r8, r3, r1				; unsigned threshold = (intervalsize * prob) >> 16;
	mov r8, r8, lsr #16			

	cmp r2, r8					; if (intervalvalue >= threshold)
	blt One
	; Zero						; {
	sub r2, r2, r8				;   intervalvalue -= threshold;
	sub r3, r3, r8				;   intervalsize -= threshold;
	sub r7, r1, r1, lsr #ADJUST_SHIFT	; new_prob = prob - (prob >> ADJUST_SHIFT);	

	.if _DEBUG
	cmp r7, #0					;   assert(new_prob > 0);
	bmi .5
	cmp r7, #0x10000			;   assert(new_prob < 0x10000);
	blt .6
	.5:
	adr r0, assert3
	swi OS_GenerateError
	.6:
	.endif

	str r7, [r9, r0, lsl #2]	;   contexts[context_index] = new_prob;
	mov r0, #0					;   bit = 0;
	ldmfd sp!, {r1, r5, r7, lr}	;   return bit
	mov pc, lr                  ; }

One:                            ; else {
	.if _DEBUG
	add r7, r2, r4
	cmp r7, r8					;   assert(intervalvalue + uncertainty <= threshold);
	ble .1
	adr r0, assert2
	swi OS_GenerateError
	.1:
	.endif

	mov r3, r8					;   intervalsize = threshold;
	add r7, r1, #0xffff >> ADJUST_SHIFT	; new_prob = prob + (0xffff >> ADJUST_SHIFT) 
	sub r7, r7, r1, lsr #ADJUST_SHIFT	;          - (prob >> ADJUST_SHIFT);

	.if _DEBUG
	cmp r7, #0					;   assert(new_prob > 0);
	bmi .4 
	cmp r7, #0x10000			;   assert(new_prob < 0x10000);
	blt .3
	.4:
	adr r0, assert3
	swi OS_GenerateError
	.3:
	.endif

	str r7, [r9, r0, lsl #2]	;   contexts[context_index] = new_prob;
	mov r0, #1					;   bit = 1;
	ldmfd sp!, {r1, r5, r7, lr}	;   return bit
	mov pc, lr                  ; }

.if _DEBUG
assert1: ;The error block
    .long 18
	.byte "assert(context_index < contexts.size()); FAILED"
	.align 4
	.long 0

assert2: ;The error block
    .long 18
	.byte "assert(intervalvalue + uncertainty <= threshold); FAILED"
	.align 4
	.long 0

assert3: ;The error block
    .long 18
	.byte "assert(new_prob > 0 && new_prob < 0x10000); FAILED"
	.align 4
	.long 0
.endif


; ============================================================================
; Implements RangeDecoder::reset().
; R9 = context buffer			(global)
; ============================================================================
RangeInit:
	mov r3, #1					; intervalsize = 1;
	mov r2, #0					; intervalvalue = 0;
	mov r4, #1					; uncertainty = 1;

	mov r1, #INIT_ONE_PROB
	mov r0, #NUM_CONTEXTS-1
.1:
	str r1, [r9, r0, lsl #2]	; contexts[context_index] = 0x8000;
	subs r0, r0, #1
	bpl .1
	mov pc, lr


; ============================================================================
; Implements (Range)Decoder::decodeNumber(int base_context).
; Decode a number >= 2 using a variable-length encoding.
; Returns the decoded number.
; R0 = base_context
; Returns R0 = number
; ============================================================================
RangeDecodeNumber:
	str lr, [sp, #-4]!
	mov r5, r0				; base_context
	mov r1, #0				; for (i = 0 ;; i++) {
.1:
	add r0, r5, r1, lsl #1	; 	context = base_context + (i * 2
	add r0, r0, #2			;           + 2);
	bl RangeDecodeBit		;   decode(context)
	cmp r0, #0
	beq .2					;   if (decode(context) == 0) break;
	add r1, r1, #1			;   i++ }
	b .1
.2:
	mov r7, #1				; int number = 1;
.3:							; for (; i >= 0 ; i--) {
	add r0, r5, r1, lsl #1	;   context = base_context + (i * 2
	add r0, r0, #1			; 		    + 1);
	bl RangeDecodeBit		;   decode(context);
	orr r7, r0, r7, lsl #1	;   number = (number << 1) | bit;
	subs r1, r1, #1			;   i--
	bpl .3					; }

	mov r0, r7
	ldr pc, [sp], #4		; return number;


; ============================================================================
; Implements LZDecoder::decode(int context).
; R0 = context
; Returns R0 = RangeDecoder::decode(NUM_SINGLE_CONTEXTS + context)
; ============================================================================
decode:
	stmfd sp!, {r1,r5,r8, lr}	; <=REGISTER PRESSURE!
	add r0, r0, #NUM_SINGLE_CONTEXTS; NUM_SINGLE_CONTEXTS + context
	bl RangeDecodeBit				; decode(...)
	ldmfd sp!, {r1,r5,r8, lr}	; <=REGISTER PRESSURE!
	mov pc, lr


; ============================================================================
; Implements LZDecoder::decodeNumber(int context_group).
; R0 = context_group
; Returns R0 = RangeDecoder::decodeNumber(NUM_SINGLE_CONTEXTS + (context_group << 8))
; ============================================================================
decodeNumber:
	stmfd sp!, {r1,r5,r8, lr}	; <=REGISTER PRESSURE!
	mov r0, r0, lsl #8
	add r0, r0, #NUM_SINGLE_CONTEXTS; NUM_SINGLE_CONTEXTS + (context_group << 8));
	bl RangeDecodeNumber			; decodeNumber(...)
	ldmfd sp!, {r1,r5,r8, lr}	; <=REGISTER PRESSURE!
	mov pc, lr


; ============================================================================
; Implements LZDecoder::decode().
; Decodes an LZ stream using the RangeDecoder.
; R9 = context				(global)
; R10 = source				(global)
; R11 = dest				(global)
; ============================================================================
LZDecode:
	str lr, [sp, #-4]!
	mov r8, #0					; int offset = 0;
    mov r12, #0x80000000        ; bit_buffer = 0x80000000

    ; bool ref = false
LZDecode_literal:				; } else {
	str r11, [sp, #-4]!			;   <=REGISTER PRESSURE!
	and r5, r11, #PARITY_MASK	;   int parity = pos & parity_mask;
	mov r1, #1					;   int context = 1;
	mov r11, #7					;   for (int i = 7 ; i >= 0 ; i--) {
.1:
	orr r0, r1, r5, lsl #8		;     (parity << 8) | context
	bl decode					;     int bit = decode((parity << 8) | context);
	orr r1, r0, r1, lsl #1		;     context = (context << 1) | bit;
	subs r11, r11, #1			;     i--
	bpl .1						;   }

	ldr r11, [sp], #4			;   <=REGISTER PRESSURE!
	strb r1, [r11], #1			;   *pDest++ = lit;
                                ; }
    ; TODO: ReportProgress callback.
    ; After literal.
    ; GetKind:
	and r0, r11, #PARITY_MASK	; int parity = pos & parity_mask;
	mov r0, r0, lsl #8
	add r0, r0, #CONTEXT_KIND
	bl decode					; ref = decode(LZEncoder::CONTEXT_KIND + (parity << 8));
    ; R0=ref
    cmp r0, #0
    beq LZDecode_literal

LZDecode_reference:
    ; bool ref = true;
    ; bool prev_was_ref = false;

	mov r0, #CONTEXT_REPEATED
	bl decode					; repeated = decode(LZEncoder::CONTEXT_REPEATED);
	cmp r0, #0					; if (!repeated) {
	beq LZDecode_readoffset

LZDecode_readlength:
	mov r0, #CONTEXT_GROUP_LENGTH
	bl decodeNumber				; int length = decodeNumber(LZEncoder::CONTEXT_GROUP_LENGTH);

	; Copied from Verifier::receiveReference(offset, length)
	sub r5, r11, r8				; pos - offset
LZDecode_copyloop:				; for (int i = 0 ; i < length ; i++) {
	ldrb r1, [r5], #1			; 	data[pos - offset + i]
	strb r1, [r11], #1			; 	data[pos + i]
	subs r0, r0, #1				;   i--
	bne LZDecode_copyloop		; }

    ; After reference.
    ; GetKind:
	and r0, r11, #PARITY_MASK	; int parity = pos & parity_mask;
	mov r0, r0, lsl #8
	add r0, r0, #CONTEXT_KIND
	bl decode					; ref = decode(LZEncoder::CONTEXT_KIND + (parity << 8));
    ; R0=ref
    cmp r0, #0
    beq LZDecode_literal

    ; bool ref = true;
    ; bool prev_was_ref = true;
LZDecode_readoffset:
	mov r0, #CONTEXT_GROUP_OFFSET
	bl decodeNumber				;   offset = decodeNumber(LZEncoder::CONTEXT_GROUP_OFFSET)
	sub r8, r0, #2				;	       - 2;
	cmp r8, #0					;
	bne LZDecode_readlength 	;   if (offset == 0) break;
	ldr pc, [sp], #4			; return true
