GaussJordanThreadData STRUCT
    matrix            QWORD ? 
    rows              DWORD ?
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
	sizeOfDouble EQU 8
	doublesInYMM EQU 4
	sizeOfYMM EQU sizeOfDouble * doublesInYMM

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
	imul	saveTo, 8		; ((rowIdx * rowSize) + colIdx) * sizeof(double)
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
	andpd xmm0, xmm1			; calculates fabs of xmm0 (resets sign bit)
	comisd xmm0, epsilon		; xmm0 (fabs(register)) < epsilon
	setb al						; set bit of al if fabs(register) <= EPSILON (about 0)
ENDM

swap_rows MACRO pointerRow1, pointerRow2, swappedElementsNum
	
ENDM


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
	
	;mov r10, rcx
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

				vmovups [rcx + rsi], ymm1	; Write row2 data into row1
				vmovups [rcx + rdi], ymm0	; Write row1 data into row2
			
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
		mov r10, rcx						; R10 = matrix pointer
		mov r11, rdx						; R11 = num of rows
		mov r15, r8							; R15 = num of cols


	inc r13									; ++curr_row
	jmp _equationsIteration					; _equatiosIteration loop


; END OF THE MAIN LOOP
_endLoop:
	
	pop_non_volatile_regs		; popping back non-volatile registers
	ret
solve_linear_system ENDP

END