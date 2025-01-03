GaussJordanThreadData STRUCT
matrix            QWORD ?
cols              DWORD ?
pivot_row_idx     DWORD ?
startRow          DWORD ?
endRow            DWORD ?
GaussJordanThreadData ENDS

.data
gaussDataArray GaussJordanThreadData 64 DUP(<>)

.const
epsilon		REAL8 1.0e-9 
signMaskDQ  dq 07FFFFFFFFFFFFFFFh
flipSignMask dq 08000000000000000h
sizeOfDouble EQU 8
doublesInYMM EQU 4
sizeOfYMM EQU sizeOfDouble * doublesInYMM
sizeOfInt EQU 4
	
; GaussJordanThreadData STRUCT offsets
matrixPtrOff	EQU 0
colsOff			EQU 8
pivotRowIdxOff	EQU 12
startRowOff		EQU	16
endRowOff		EQU 20

.code
; MACRO push_non_volatile_regs
; Pushes all non-volatile registers to stack.
; (May be done better?)
; To pop registers back use pop_non_volatile_regs.
;
; No args given
push_non_volatile_regs MACRO
push R12
push R13
push R14
push R15
push RDI
push RSI
push RBX
push RBP
ENDM


; MACRO pop_non_volatile_regs
; Pushes all non-volatile registers to stack.
; (May be done better?)
;
; No args given
pop_non_volatile_regs MACRO
pop RBP
pop RBX
pop RSI
pop RDI
pop R15
pop R14
pop R13
pop R12
ENDM


; MACRO write_if_smaller
; if(saveTo > compared) {
;	saveTo = compared;
; }
;
; args:
; saveTo -> register to compare and save result to
; compared -> register to compare value and copy from
write_if_smaller MACRO saveTo, compared
cmp compared, saveTo
cmovl saveTo, compared
ENDM


; MACRO get_matrix_offset
; Saves offset into given register
;
; args:
; rowSize -> size of row in matrix
; rowIdx -> index of searched row
; colIdx -> index of searched col
; saveTo -> register to save result in
get_matrix_offset MACRO rowSize, rowIdx, colIdx, saveTo
mov		saveTo, rowIdx
imul	saveTo, rowSize
add		saveTo, colIdx 
shl		saveTo, 3		; ((rowIdx * rowSize) + colIdx) * sizeof(double)
ENDM


; MACRO is_zero
; Checks if given register value is less than ESPILON.
; Returns (through RAX):
;	- 0: if it's not zero
;	- 1: if it's zero
;
; args:
; registerName -> name of the register to check contents
is_zero MACRO register
xor rax, rax				; rax = 0
movsd xmm0, register		; xmm0 = register 
movsd xmm1, signMaskDQ		; prepare mask for fabs
andpd xmm0, xmm1			; perform fabs (resets sign bit)
comisd xmm0, epsilon		; compare fabs(xmm0) to epsilon
setb al						; set bit of al if fabs(register) <= EPSILON (about 0)
ENDM


eliminate_on_thread PROC 
push rsi
	; RCX <-> threadDataPtr
	; save data to registers
	mov		rdx,	QWORD PTR [rcx]					; RDX = double* matrix
	movsxd	r8,		DWORD PTR [rcx + colsOff]		; R8  = int cols (rowSize)
	movsxd	r9,		DWORD PTR [rcx + pivotRowIdxOff]; R9  = int pivotRowidx
	movsxd	r10,	DWORD PTR [rcx + startRowOff]	; R10 = int startRowIdx
	movsxd	r11,	DWORD PTR [rcx + endRowOff]		; R11 = int endRowIdx

; pivotColIdx == pivotRowIdx
; startRowIdx == currRow
_elimStart:
	cmp r10, r11	; if (currRow >= endRowIdx)
	jge _finishElim ;	break

	cmp r10, r9		; if (currRow == pivotRow)
	je _endLoop		;	continue	(skip row)

	get_matrix_offset r8, r10, r9, rcx	; factor = value at (currRow, pivotColIdx)
	movsd xmm0, QWORD PTR [rdx + rcx]	; save this at xmm0	

	is_zero xmm0	; if (isZero(val))
	cmp rax, 1		;	continue (skip row)
	je	_endLoop

	movsd xmm0, QWORD PTR [rdx + rcx]
	movsd xmm1, flipSignMask	; load flipping sign mask
	xorpd xmm0, xmm1			; flip the sign of xmm0
				; sign is flipped for vectorization simplicity
				; more about in _elimLoopAvx

	vbroadcastsd ymm4, xmm0 
	mov rax, r8		; RAX <-> elementsToSubtract
	sub rax, r9		; elementsToSubtract = rowSize - currRow(pivotColIdx)

	get_matrix_offset r8, r9, r9, rsi	; Load pivot first element offset
	_elimLoopAvx:
	cmp rax, 4						; if (elementsLeft < 4)
	jl _elimLoopNormal				;	jump of out 

	vmovupd ymm2, ymmword ptr [rdx + rcx]		; Load destiny values
	vmovupd ymm3, ymmword ptr [rdx + rsi]		; Load pivot values

	vfmadd231pd ymm2, ymm3, ymm4	; ymm2 += ymm3 * ymm4
						; multiply pivot values by negated factor
						; ymm2 += pivotVals * (-factor)
						; ymm2 -= pivotVals * factor

	vmovupd ymmword ptr [rdx + rcx], ymm2		; save result

	add rsi, sizeOfYMM				; move pivot ptr to next values
	add rcx, sizeOfYMM				; move goal ptr to next values
	sub rax, doublesInYMM			; reduce number of elements left
	jmp _elimLoopAvx				

	_elimLoopNormal:
	cmp rax, 0							; perform if there are elements left
	jle _endLoop						; end if no left

	movsd xmm1, QWORD PTR [rdx + rsi]	; load pivot value
	mulsd xmm1, xmm0					; multiply pivot by factor
	movsd xmm2, QWORD PTR [rdx + rcx]	; load row to subtract from
	addsd xmm2, xmm1					; subtract (add negated factor * pivotVal)
	movsd QWORD PTR [rdx + rcx], xmm2	; save result

	add rsi, sizeOfDouble				; move pivot ptr to next value
	add rcx, sizeOfDouble				; move goal element to next value
	dec rax								; decrement number of elements left
	jmp _elimLoopNormal


_endLoop:
	inc r10
	jmp _elimStart

_finishElim:

	pop rsi

	xor rax, rax	; return 0
	ret
eliminate_on_thread ENDP




; PROCEDURE solve_linear_system
; Solves linear system in-place.
; Returns (through RAX):
;  - 0: system has no solution,
;  - 1: system has 1 solution,
;  - 2: system has infinite number of solutions.
;
; args:
; double* matrix -> RCX
; int rows -> RDX
; int cols -> R8
; int num_threads -> R9
solve_linear_system PROC
	
; PREPARING MAIN LOOP
	push_non_volatile_regs		; save non-volatile registers
	
	mov rbx, r9					; RBX = num of threads

	mov r12, r8					; possible_iterations <-> R12
	dec r12						; variables_num = cols - 1
	write_if_smaller r12, rdx	; possible_iterations = min(rows, variables_num)

	xor r13, r13				; curr_row <-> R13 = 0


; MAIN LOOP
_equationsIteration:
	cmp r13, r12							; if(curr_row >= possible_iterations)
	jge	_endLoop							;	end the loop

	get_matrix_offset r8, r13, r13, r14		; pivot_ptr_offset <-> R14
	
	movsd xmm0, QWORD PTR [rcx + r14]		; pivot_val <-> xmm3

	is_zero xmm0							; if (pivot_val != 0.0)
	cmp rax, 0								;	 move along
	je _pivot_row_normalization				; else 
						;	fallthrough and try swap rows

; IF PIVOT IS ZERO FIND NON ZERO PIVOT AND SWAP ROWS
_pivot_is_zero:							; find non_zero pivot row
	mov r11, r13						; preparing loop (it_row = curr_row + 1)		
	inc r11

	_itStart:
		cmp r11, rdx							; if(it_row >= rowsNum)
		jge _notFound							;	jump to not found

		get_matrix_offset r8, R11, r13, r10		; get element offset into r10
		movsd xmm0, QWORD PTR [rcx + r10]		; move element value into xmm0
		is_zero xmm0							; check if xmm0 == 0? (result in rax)
		cmp rax, 0								; if is_zero(xmm0) == false
		je _found								; jump to swap_rows

		inc r11									; else increment curr_row
		jmp _itStart

		_notFound:
		inc r13									; non-zero pivot not found => skip iteration
		jmp _equationsIteration

		_found:										; found, so swap rows
		mov rdi, r10							; RDI <-> element A to swap ptr
		mov rsi, r14 							; RSI <-> element B to swap ptr
		
		mov r10, r8								; R10 <-> elementsToSwap
		sub r10, r13							; elementsToSwap  = rowSize - columnsToReduce

		_avxSwap:	; copy as may elements as possible using AVX 
			cmp r10, 4					; if there aren't enough elements to swap with AVX
			jl _simpleSwap				; jump to normal swap
			
			vmovupd ymm0, [rcx + rsi]	; Load 32 bytes from row1
			vmovupd ymm1, [rcx + rdi]	; Load 32 bytes from row2

			vmovupd [rcx + rsi], ymm1	; Write row2 data into row1
			vmovupd [rcx + rdi], ymm0	; Write row1 data into row2
			
			add rsi, sizeOfYMM			; increment ptr to next elements
			add rdi, sizeOfYMM			; increment ptr to next elements
			sub r10, doublesInYMM		; decrease number of elements left by 4
			jmp _avxSwap

			
		_simpleSwap:	; copy element one by one
			cmp r10, 0							; if there aren't any elements left to swap
			jle _pivot_row_normalization		; jump to code when pivot is normalization
			
			movsd xmm0, QWORD PTR [rcx + rsi]	; load value A from ptr 1
			movsd xmm1, QWORD PTR [rcx + rdi]	; load value B from ptr 2

			movsd QWORD PTR [rcx + rsi], xmm1	; save value B to ptr 1
			movsd QWORD PTR [rcx + rdi], xmm0	; save value A to ptr 2

			add rsi, sizeOfDouble				; move by sizeof(double)
			add rdi, sizeOfDouble				; move by sizeof(double)
			dec r10								; decrement number of elements left
			jmp _simpleSwap


; IF PIVOT IS NON ZERO CONTINUE NORMALLY
_pivot_non_zero:
_pivot_row_normalization:
	
	get_matrix_offset r8, r13, r13, rsi	; RSI = currentPivotOffset	

	mov r10, r8							; R10 <-> elementsToNormalize
	sub r10, r13						; elementsToNormalize = rowSize - columnsToNormalize

	movsd xmm0, QWORD PTR [rcx + r14]	; xmm0 = current pivot value

	vbroadcastsd ymm1, xmm0 			; YMM1 = vector of pivot values

	_avxNormalization:
		cmp r10, 4					; If there aren't enough elements to normalize with AVX
		jl _simpleNormalization		; Jump to normal division

		vmovupd ymm0, [rcx + rsi]	; Load 4 doubles from row
		vdivpd ymm0, ymm0, ymm1		; Write row2 data into row
		vmovupd [rcx + rsi], ymm0	; Save 4 doubles to row
			
		add rsi, sizeOfYMM			; increment ptr to next elements
		sub r10, doublesInYMM		; decrease number of elements left by 4
		jmp _avxNormalization		; loop 

	_simpleNormalization:
		cmp r10, 0							; if there aren't any elements left to swap
		jle _elimination					; jump to elimination when finished
			
		movsd xmm1, QWORD PTR [rcx + rsi]	; load element value to xmm1
		divsd xmm1, xmm0					; divide value by pivot
		movsd QWORD PTR [rcx + rsi], xmm1	; load divided value to memory

		add rsi, sizeOfDouble				; move by sizeof(double)
		dec r10								; decrement number of elements left
		jmp _simpleNormalization			; loop

_elimination:
	push rcx
	push rdx
	push r8

	mov QWORD PTR[gaussDataArray + matrixPtrOff],	rcx
	mov DWORD PTR[gaussDataArray + colsOff],		r8d
	mov DWORD PTR[gaussDataArray + pivotRowIdxOff],	r13d
	mov DWORD PTR[gaussDataArray + startRowOff],	0
	mov DWORD PTR[gaussDataArray + endRowOff],		edx

	lea rcx, [gaussDataArray]

	call eliminate_on_thread

	pop r8
	pop rdx
	pop rcx

	inc r13									; ++curr_row
	jmp _equationsIteration					; _equatiosIteration loop


; END OF THE MAIN LOOP
_endLoop:
	
	pop_non_volatile_regs		; popping back non-volatile registers

	mov rax, 2
	ret
solve_linear_system ENDP

END