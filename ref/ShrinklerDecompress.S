; Copyright 1999-2015 Aske Simon Christensen.
;
; The code herein is free to use, in whole or in part,
; modified or as is, for any legal purpose.
;
; No warranties of any kind are given as to its behavior
; or suitability.


INIT_ONE_PROB		=	$8000
ADJUST_SHIFT		=	4
SINGLE_BIT_CONTEXTS	=	1
NUM_CONTEXTS		=	1536


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

ShrinklerDecompress:
	; Preserve registers d2-d7, a-a6 on the stack.
	movem.l	d2-d7/a4-a6,-(a7)		; *(--pStack) = {d2-d7,a4-a6}

	move.l	a0,a4					; pIn = compressed source.
	move.l	a1,a5					; pOut = decompressed dest.
	move.l	a1,a6					; pOutBase = decompressed dest base.

	; Init range decoder state
	moveq.l	#0,d2					; interval_value=0
	moveq.l	#1,d3					; interval_size=1
	moveq.l	#1,d4					; bit_buffer=1
	ror.l	#1,d4					; bit_buffer=0x80000000

	; Pushes 1536 items on the stack. (3K)
	; Init probabilities
	move.l	#NUM_CONTEXTS,d6		; bit_context=NUM_CONTEXTS
.init:	move.w	#INIT_ONE_PROB,-(a7); *(--pStack)=INIT_ONE_PROB [WORD]
	subq.w	#1,d6					; bit_context--
	bne.b	.init					; if bit_context!=0 goto .init

	; D6 = 0
	; bool ref = false => start with literal.
.lit:
	; Literal
	addq.b	#1,d6					; bit_context++ [BYTE]
.getlit:
	bsr.b	GetBit					; [C, X]=GetBit()
	addx.b	d6,d6					; bit_context=(bit_context << 1) | X
	bcc.b	.getlit					; if C=0 goto .getlit
	move.b	d6,(a5)+				; *pOut++ = bit_context [BYTE]
	bsr.b	ReportProgress			; ReportProgress()
.switch:
	; After literal
	bsr.b	GetKind					; [C, X]=GetKind()
; => Note that C=bool ref (0=lit, 1=reference).
	bcc.b	.lit					; if C=0 goto .lit
	; Reference
	moveq.l	#-1,d6					; bit_context=-1
	bsr.b	GetBit					; [C, X]=GetBit()
	bcc.b	.readoffset				; if C=0 goto .readoffset
.readlength:
	moveq.l	#4,d6					; number_context=4 (=NUM_SINGLE_CONTEXTS + CONTEXT_GROUP_LENGTH)
	bsr.b	GetNumber				; d0=GetNumber(number_context)
.copyloop:
	move.b	(a5,d5.l),(a5)+			; *pOut=pOut[d5] [BYTE]
	subq.l	#1,d0					; d0--
	bne.b	.copyloop				; if d0!=0 goto .copyloop
	bsr.b	ReportProgress			; ReportProgres()
	; After reference
	bsr.b	GetKind					; [C, X]=GetKind()
; => Note that C=bool ref (0=lit, 1=reference).
	bcc.b	.lit					; if C=0 goto .lit
.readoffset:
	moveq.l	#3,d6					; number_context=3 (=NUM_SINGLE_CONTEXTS + CONTEXT_GROUP_OFFSET)
	bsr.b	GetNumber				; d0=GetNumber(number_context)
	moveq.l	#2,d5					; d5=2
	sub.l	d0,d5					; d5=2-d0 = -offset
	bne.b	.readlength				; if d5 !=0 goto .readlength

	; Pops 1536 items off the stack by reseting the stack ptr.
	lea.l	NUM_CONTEXTS*2(a7),a7	; pStack+=NUM_CONTEXTS*2
	; Pop preserved registers off the stack.
	movem.l	(a7)+,d2-d7/a4-a6		; {d2-d7,a4-a6} = *pStack++
	rts

ReportProgress:
	move.l	a2,d0					; d0=callback_addr
	beq.b	.nocallback				; if d0=0 goto .nocallback
	move.l	a5,d0					; d0=pOut
	sub.l	a6,d0					; d0-=pOutBase (=bytes_written)
	move.l	a3,a0					; a0=callback_arg
	jsr	(a2)						; (*callback_addr)(bytes_written,callback_arg)
.nocallback:
	rts
; => Can free a2,a3 for more general use.

GetKind:
	; Use parity as context
	move.l	a5,d6					; bit_context=pOut
	and.l	d7,d6					; bit_context=pOut & parity_context
	lsl.w	#8,d6					; bit_context=bit_context<<8
	bra.b	GetBit					; goto GetBit
; => Note that C=bool ref (0=lit, 1=reference).
; => Note that d7 is constant so can be assembled in and freed.

GetNumber:
	; D6 = Number context

	; Out: Number in D0
	lsl.w	#8,d6					; number_context=number_context<<8 [WORD]
.numberloop:
	addq.b	#2,d6					; number_context+=2
	bsr.b	GetBit					; [C, X]=GetBit()
	bcs.b	.numberloop				; if C=1 goto .numberloop
	moveq.l	#1,d0					; d0=1
	subq.b	#1,d6					; number_context-=1 [BYTE]
.bitsloop:
	bsr.b	GetBit					; [C, X]=GetBit()
	addx.l	d0,d0					; d0=(d0 << 1) | X
	subq.b	#2,d6					; number_context-=2
	bcc.b	.bitsloop				; if C=0 goto .bitsloop
	rts

	; D6 = Bit context

	; D2 = Range value
	; D3 = Interval size
	; D4 = Input bit buffer

	; Out: Bit in C and X

readbit:
	add.l	d4,d4					; bit_buffer=bit_buffer << 1, X=top bit
	bne.b	nonewword				; if bit_buffer!=0 goto nonewword
	move.l	(a4)+,d4				; bit_buffer=*pIn++ [LONG]
	addx.l	d4,d4					; bit_buffer=(bit_buffer << 1) | X
nonewword:
	addx.w	d2,d2					; interval_value=(interval_value << 1) | X
	add.w	d3,d3					; interval_size=interval_size << 1
GetBit:
	tst.w	d3						; [clear C, preserve X?]
	bpl.b	readbit					; if interval_size<0x8000 goto readbit

	lea.l	4+SINGLE_BIT_CONTEXTS*2(a7,d6.l),a1	; a1=pStack+4+SINGLE_BIT_CONTEXTS*2+bit_context
	add.l	d6,a1					; a1+=bit_context (=pContext)
	; Looking up one of the contexts from the stack.
	; d1=pStack[4+SINGLE_BIT_CONTEXT*2+bit_context*2]
	move.w	(a1),d1					; prob=*pStackContext	[WORD]
	; D1 = One prob

	lsr.w	#ADJUST_SHIFT,d1		; prob=prob>>ADJUST_SHIFT
	sub.w	d1,(a1)					; *pContext-=prob
	add.w	(a1),d1					; prob+=*pContext

	mulu.w	d3,d1					; threshold=interval_size*prob
	swap.w	d1						; threshold=threshold>>16

	sub.w	d1,d2					; interval_value-=threshold
	blo.b	.one					; if C=1 goto .one
.zero:
	; new_prob = prob - (prob >> ADJUST_SHIFT);	
	; oneprob = oneprob * (1 - adjust) = oneprob - oneprob * adjust
	sub.w	d1,d3					; interval_size-=adjust
	; 0 in C and X
	rts
.one:
	; new_prob = prob + (0xffff >> ADJUST_SHIFT) - (prob >> ADJUST_SHIFT);
	; oneprob = 1 - (1 - oneprob) * (1 - adjust) = oneprob - oneprob * adjust + adjust
	add.w	#$ffff>>ADJUST_SHIFT,(a1)	; *pContext+=0xffff>>ADJUST_SHIFT
	move.w	d1,d3					; interval_size=adjust [WORD]
	add.w	d1,d2					; interval_value+=adjust [WORD]
	; 1 in C and X
	rts
