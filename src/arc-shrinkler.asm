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

.equ _ENDIAN_SWAP, 0			; swap byte in long word at runtime.

.equ INIT_ONE_PROB, 0x8000
.equ ADJUST_SHIFT, 4
.equ NUM_CONTEXTS, 1536
.equ PARITY_MASK, 0				; byte or short word data.

.equ NUM_SINGLE_CONTEXTS, 1

.equ CONTEXT_KIND, 0
.equ CONTEXT_REPEATED, -1
.equ CONTEXT_GROUP_LIT, 0
.equ CONTEXT_GROUP_OFFSET, 2
.equ CONTEXT_GROUP_LENGTH, 3

; ============================================================================
; ARM Register Usage.
; ============================================================================

; R0  = parameter / return value
; R1  = temp                    (DecodeNumber, LZDecodeLiteral)
; R2  = unsigned intervalvalue 	(RangeDecoder)
; R3  = unsigned intervalsize	(RangeDecoder)
; R4  = temp                    (local only)
; R5  = unused
; R6  = context_index           (parameter)
; R7  = temp                    (DecodeNumber, LZDecodeLiteral)
; R8  = int offset              (LZDecode)
; R9  = context				    (global)
; R10 = source				    (global)
; R11 = dest				    (global)
; R12 = bit_buffer			    (RangeDecoder)


; ============================================================================
; Implements RangeDecoder::decode(int context_index).
; Decode a bit in the given context.
; Returns the decoded bit value.
; R6 = context_index
; Returns R0 = bit
; ============================================================================
RangeDecodeBit:
	.if _DEBUG
	cmp r6, #-1					; assert(context_index < contexts.size());
	blt .4
	cmp r6, #NUM_CONTEXTS		; assert(context_index < contexts.size());
	blt .3
	.4:
	adr r0, assert1
	swi OS_GenerateError
	.3:
	.endif

.1:
	cmp r3, #0x8000				; while (intervalsize < 0x8000) {
	bge .2
	mov r3, r3, lsl #1			; 	intervalsize <<= 1;

; RangeDecoder::getBit().
    movs r12, r12, lsl #1       ;   bit_buffer=bit_buffer << 1, C=top bit.
    bne .7                      ;   if bit_buffer!=0 goto nonewword
    ldr r12, [r10], #4          ;   bit_buffer = *pCompressed++ [3210]

    .if _ENDIAN_SWAP
    ; Argh! Endian swap word for ARM.
    mov r0, r12, lsr #24        ; [xxx3]
    orr r0, r0, r12, lsl #24    ; [0xx3]
    and r4, r12, #0x00ff0000
    orr r0, r0, r4, lsr #8      ; [0x23]
    and r4, r12, #0x0000ff00
    orr r12, r0, r4, lsl #8     ; [0123]
    .endif

    ; This is genius - last bit will always be 1 and signify that all bits have been consumed.
    adcs r12, r12, r12          ;   bit_buffer=(bit_buffer << 1) | C, C=top bit
.7:                             ; nonewword:
    adc r2, r2, r2             ; 	intervalvalue = (intervalvalue << 1) | getBit();
	b .1						; }
.2:

	ldr r0, [r9, r6, lsl #2]	; unsigned prob = contexts[context_index];

	; R4 =	unsigned threshold
	mul r4, r3, r0				; unsigned threshold = (intervalsize * prob) >> 16;
	mov r4, r4, lsr #16			

	; R0 =	unsigned new_prob = prob - (prob >> ADJUST_SHIFT);	
	sub r0, r0, r0, lsr #ADJUST_SHIFT

	cmp r2, r4					; if (intervalvalue >= threshold)
	blt One
	; Zero
	.if _DEBUG
	cmp r0, #0					;   assert(new_prob > 0);
	bmi .5
	cmp r0, #0x10000			;   assert(new_prob < 0x10000);
	blt .6
	.5:
	adr r0, assert3
	swi OS_GenerateError
	.6:
	.endif

	str r0, [r9, r6, lsl #2]	;   contexts[context_index] = new_prob;
	sub r2, r2, r4				;   intervalvalue -= threshold;
	sub r3, r3, r4				;   intervalsize -= threshold;
	mov r0, #0					;   bit = 0;
	mov pc, lr       	        ;   return bit

One:                            ; } else {
    ; R0 =	unsigned new_prob = prob - (prob >> ADJUST_SHIFT) + (0xffff >> ADJUST_SHIFT);	
	add r0, r0, #0xffff >> ADJUST_SHIFT

	.if _DEBUG
	cmp r0, #0					;   assert(new_prob > 0);
	bmi .4 
	cmp r0, #0x10000			;   assert(new_prob < 0x10000);
	blt .3
	.4:
	adr r0, assert3
	swi OS_GenerateError
	.3:
	.endif

	str r0, [r9, r6, lsl #2]	;   contexts[context_index] = new_prob;
	mov r3, r4					;   intervalsize = threshold;
	mov r0, #1					;   bit = 1;
	mov pc, lr       	        ;   return bit

.if _DEBUG
assert1: ;The error block
    .long 18
	.byte "assert(context_index < contexts.size()); FAILED"
	.align 4
	.long 0

assert3: ;The error block
    .long 18
	.byte "assert(new_prob > 0 && new_prob < 0x10000); FAILED"
	.align 4
	.long 0
.endif


; ============================================================================
; Implements (Range)Decoder::decodeNumber(int base_context).
; Decode a number >= 2 using a variable-length encoding.
; Returns the decoded number.
; R6 = base_context
; Returns R7 = number
; ============================================================================
RangeDecodeNumber:
	str lr, [sp, #-4]!
    mov r1, #0              ; i=0
.1:
	add r6, r6, #2          ;   context = base_context + (i * 2)
	bl RangeDecodeBit		;   decode(context)
	cmp r0, #0
	beq .2					;   if (decode(context) == 0) break;
    add r1, r1, #1          ;   i++
    b .1
.2:
    sub r6, r6, #1
	mov r7, #1				; int number = 1;
.3:							; 
	bl RangeDecodeBit		;   decode(context);
	orr r7, r0, r7, lsl #1	;   number = (number << 1) | bit;
    sub r6, r6, #2          ;   context = base_context + (i * 2)
	subs r1, r1, #1			;   i--
	bpl .3					; 
	ldr pc, [sp], #4		; return number;


; ============================================================================
; Implements LZDecoder::decode().
; Decodes an LZ stream using the RangeDecoder.
; R9 = context				(global)
; R10 = source				(global)
; R11 = dest				(global)
; ============================================================================

ShrinklerDecompress:
	stmfd sp!, {r11, lr}
	mov r2, #0					; intervalvalue = 0;
	mov r3, #1					; intervalsize = 1;
    mov r6, #0                  ; bit_context = 0;
	mov r8, #0					; int offset = 0;
    mov r12, #0x80000000        ; bit_buffer = 0x80000000

    ; RangeDecoder::reset().
	mov r1, #INIT_ONE_PROB
	mov r0, #NUM_CONTEXTS-1
.1:
	str r1, [r9, r0, lsl #2]	; contexts[context_index] = 0x8000;
	subs r0, r0, #1
	bpl .1

    add r9, r9, #NUM_SINGLE_CONTEXTS*4

LZDecode_literal:
    ; bool ref = false

	; R6 contains (parity << 8) from GetKind...
	mov r1, r6
	mov r6, #1					;   int context = 1;
.1:
    bic r6, r6, #0xff00         ;     remove parity bits
	orr r6, r6, r1      		;     (parity << 8) | context
	bl RangeDecodeBit			;     int bit = decode((parity << 8) | context);
    bic r6, r6, #0xff00         ;     remove parity bits
	orr r6, r0, r6, lsl #1		;     context = (context << 1) | bit;
	cmp r6, #0x100				;   <- byte carry.
	blt .1
	strb r6, [r11], #1			;   *pDest++ = lit;

    ; After literal.
    ; GetKind:
	.if PARITY_MASK != 0
	and r6, r11, #PARITY_MASK	; int parity = pos & parity_mask;
	mov r6, r6, lsl #8
	add r6, r6, #CONTEXT_KIND
	.else
	mov r6, #CONTEXT_KIND
	.endif
	bl RangeDecodeBit			; ref = decode(LZEncoder::CONTEXT_KIND + (parity << 8));
    ; R0=ref
    cmp r0, #0
    beq LZDecode_literal

LZDecode_reference:
    ; bool ref = true;
    ; bool prev_was_ref = false;

    mov r6, #CONTEXT_REPEATED
	bl RangeDecodeBit			; repeated = decode(LZEncoder::CONTEXT_REPEATED);
	cmp r0, #0					; if (!repeated) {
	beq LZDecode_readoffset

LZDecode_readlength:
	mov r6, #CONTEXT_GROUP_LENGTH<<8; (context_group << 8)
	bl RangeDecodeNumber			; int length = decodeNumber(LZEncoder::CONTEXT_GROUP_LENGTH);

	; Copied from Verifier::receiveReference(offset, length)
	sub r4, r11, r8				; pos - offset
.1:				                ; for (int i = 0 ; i < length ; i++) {
	ldrb r1, [r4], #1			; 	data[pos - offset + i]
	strb r1, [r11], #1			; 	data[pos + i]
	subs r7, r7, #1				;   i--
	bne .1						; }

    ; TODO: ReportProgress callback.

    ; After reference.
    ; GetKind:
	.if PARITY_MASK != 0
	and r6, r11, #PARITY_MASK	; int parity = pos & parity_mask;
	mov r6, r6, lsl #8
	add r6, r6, #CONTEXT_KIND
	.else
	mov r6, #CONTEXT_KIND
	.endif
	bl RangeDecodeBit			; ref = decode(LZEncoder::CONTEXT_KIND + (parity << 8));
    ; R0=ref
    cmp r0, #0
    beq LZDecode_literal

LZDecode_readoffset:
    ; bool ref = true;
    ; bool prev_was_ref = true;

	mov r6, #CONTEXT_GROUP_OFFSET<<8; (context_group << 8)
	bl RangeDecodeNumber			; offset = decodeNumber(LZEncoder::CONTEXT_GROUP_OFFSET)
	sub r8, r7, #2				;          - 2;
	cmp r8, #0					;
	bne LZDecode_readlength 	;   if (offset == 0) break;

	; Return number of bytes written in R0.
	ldmfd sp!, {r10, lr}
	sub r0, r11, r10
	mov pc, lr					; return
