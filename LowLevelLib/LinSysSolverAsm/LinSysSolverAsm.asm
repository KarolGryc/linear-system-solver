INCLUDELIB kernel32.lib

EXTERN CreateThread: PROC
EXTERN WaitForMultipleObjects: PROC
EXTERN CloseHandle: PROC

GaussJordanThreadData STRUCT
startRow          QWORD ?
endRow            QWORD ?
GaussJordanThreadData ENDS

.const
	MAX_THREADS     EQU 64
	epsilon			REAL4 1.0e-9 
	zeroVal			dd 0.0
	maxThreads		dq MAX_THREADS
	rmSignMask		dd 07FFFFFFFh
	flipSignMask	dd 080000000h
	floatSize		EQU 4
	ymmFloats		EQU 8
	ymmSize			EQU floatSize * ymmFloats
	intSize			EQU 4
	
	; GaussJordanThreadData STRUCT offsets
	startRowOff		EQU	0
	endRowOff		EQU 8

.data 
	matrixAddr	dq	0
	numCols		dq	0
	numRows		dq	0
	numThreads	dq	1
	pivotRowIdx dq	0
    threads         QWORD MAX_THREADS DUP(?)
    threadData      GaussJordanThreadData MAX_THREADS DUP(<?>)
.code

; <------------------------------------------------------->
; MACRO write_if_smaller
; saveTo = min(saveTo, compared)
;
; args:
; saveTo -> register to compare and save result to
; compared -> register to compare value and copy from
write_min MACRO saveTo, compared
	cmp saveTo, compared
	cmovg saveTo, compared
ENDM
; <------------------------------------------------------->



; <------------------------------------------------------->
; MACRO mtx_off
; Saves offset into given register
;
; args:
; saveTo -> register to save result in
; rowSize -> size of row in matrix
; rowIdx -> index of searched row
; colIdx -> index of searched col
mtx_off MACRO saveTo, rowSize, rowIdx, colIdx
	mov		saveTo, rowIdx
	imul	saveTo, rowSize
	add		saveTo, colIdx	; (rowIdx * rowSize) + colIdx	
ENDM
; <------------------------------------------------------->



; <------------------------------------------------------->
; MACRO is_zero
; Checks if given register value is less than ESPILON.
; Returns (through RAX):
;	- 0: if it's not zero
;	- 1: if it's zero
;
; args:
; registerName -> name of the register to check contents
is_zero MACRO register
	movss xmm1, dword ptr [rmSignMask]  
	andps register, xmm1 ; perform fabs (resets sign bit)
	comiss register, epsilon
ENDM
; <------------------------------------------------------->



; <------------------------------------------------------->
; PROCEDURE eliminate_on_thread
; Executes elimination on single thread
eliminate_on_thread PROC
	push rsi
	; RCX <-> threadDataPtr
	; save data to registers
	mov	rdx,	matrixAddr	; RDX = float* matrix
	mov	r8,		numCols		; R8  = int cols (rowSize)
	mov	r9,		pivotRowIdx	; R9  = int pivotRowidx (pivotColIdx)
	mov	r10,	QWORD PTR [rcx + startRowOff]	; R10 = int startRowIdx (currRow)
	mov	r11,	QWORD PTR [rcx + endRowOff]		; R11 = int endRowIdx

_elimStart:
	cmp r10, r11	; if (currRow >= endRowIdx)
	jge _finishElim ;	break

	cmp r10, r9		; if (currRow == pivotRow)
	je _endLoop		;	continue	(skip row)

	mtx_off rax, r8, r10, r9 ; factor = value at (currRow, pivotColIdx)

	movss xmm0, DWORD PTR [rdx + rax * floatSize] ; load factor to XMM0
	movss xmm5, xmm0
	is_zero xmm0	; if (isZero(val))
	jbe _endLoop	;	continue (skip row)

	movss xmm1, flipSignMask	; load flipping sign mask
	xorps xmm5, xmm1			; flip the sign of xmm0
	vbroadcastss ymm4, xmm5		; sign is flipped for vectorization
								; factor vector

	mov rcx, r8	; RCX = columns to eliminate
	sub rcx, r9

	mtx_off rsi, r8, r9, r9 	; Load pivot first element offset
	_elimLoopAvx:
		cmp rcx, 8						; if (elementsLeft < 4)
		jl _elimLoopNormal				;	jump of out 

		vmovups ymm2, ymmword ptr [rdx + rax * floatSize]	; Load destiny values
		vmovups ymm3, ymmword ptr [rdx + rsi * floatSize]	; Load pivot values
		vfmadd231ps ymm2, ymm3, ymm4	; ymm2 += ymm3 * ymm4 (ymm2 += pivotVals * (-factor))
		vmovups ymmword ptr [rdx + rax * floatSize], ymm2	; save result

		add rsi, ymmFloats				; move pivot ptr to next values
		add rax, ymmFloats				; move goal ptr to next values
		sub rcx, ymmFloats
		jmp _elimLoopAvx				

	_elimLoopNormal:
		cmp rcx, 0			; perform if there are elements left
		jle _endLoop		; end if no left

		movss xmm1, dword ptr [rdx + rsi * floatSize]	; load pivot value
		mulss xmm1, xmm5								; multiply pivot by factor
		movss xmm3, dword ptr [rdx + rax * floatSize]	; load row to subtract from
		addss xmm3, xmm1								; subtract (add negated factor * pivotVal)
		movss dword ptr [rdx + rax * floatSize], xmm3	; save result

		inc rsi		; move pivot ptr to next value
		inc rax		; move goal element to next value
		dec rcx		; decrement number of elements left
		jmp _elimLoopNormal

_endLoop:
	inc r10
	jmp _elimStart

_finishElim:
	pop rsi
	xor rax, rax	; return 0
	ret
eliminate_on_thread ENDP
; <------------------------------------------------------->



; <------------------------------------------------------->
; MACRO prepare_thread_array
; Prepares global variables for execution
prepare_thread_array MACRO mtxAddr, nRows, nCols, nThreads
	mov matrixAddr, mtxAddr
	mov numCols, nCols
	mov numRows, nRows
	mov numThreads, nThreads
ENDM
; <------------------------------------------------------->



; <------------------------------------------------------->
; PROCEDURE solve_linear_system
; Solves linear system in-place.
; Returns (through RAX):
;  - 0: system has no solution,
;  - 1: system has 1 solution,
;  - 2: system has infinite number of solutions.
;
; args:
; float* matrix -> RCX
; int rows -> RDX
; int cols -> R8
; int num_threads -> R9
solve_linear_system PROC
	
; PREPARING MAIN LOOP
	push r12
	push r13
	push r14
	push r15
	push rsi
	push rdi
								; R8 = row_size
	mov rax, r9					; RBX = num_of_threads
	write_min rax, qword ptr [maxThreads]

	prepare_thread_array rcx, rdx, r8, rax

	mov r15, rdx				; R15 = num_of_rows
	mov r12, r8					; R12 = num_of_iterations
	dec r12						; variables_num = cols - 1
	write_min r12, r15			; num_of_iterations = min(rows, variables_num)

	xor r13, r13				; R13 = curr_row


; MAIN LOOP
_solveLoopStart:
	cmp r13, r12		; if(curr_row >= possible_iterations)
	jge	_solveLoopEnd	; end the loop

	mtx_off r14, r8, r13, r13	; R14 = curr_pivot_element_offset
								; pivot_el_row == pivot_el_col
	
	movss xmm0, dword ptr [rcx + r14 * floatSize] ; XMM0 = pivot_val

	is_zero xmm0				; if (pivot_val == 0.0) swap rows
	jnbe _pivot_normalization	; else goto normalization

	_pivot_is_zero:
		mov rdx, r13	; RDX = it_row iterator for searching non zero		
		inc rdx			; it_row = curr_row + 1	

		_itStart:
			cmp rdx, r15	; if(it_row >= rowsNum)
			jge _notFound	;	jump to not found

			mtx_off r10, r8, rdx, r13 						; get element offset into r10
			movss xmm0, dword ptr [rcx + r10 * floatSize]	; move element value into xmm0
		
			is_zero xmm0 ; if (xmm0 == 0.0)
			jnbe _found	 ;	jump to swap_rows

			inc rdx		 ; else
			jmp _itStart ;	check next row

		_notFound:
			inc r13				
			jmp _solveLoopStart	; skip iteration

		_found:	; swap rows
			mov rsi, r13; RSI = element A to swap ptr
			mov rdi, r10; RDI = element B to swap ptr

			mov r10, r8	
			sub r10, r13
			mov r11, r10 ; R11 = iterations of simple swap
			shr r10, 3 ; R10 = iterations with AVX
			and r11, 7 ; R11 = iterations with AVX

			_avxSwap:
				test r10, r10
				jz _simpleSwap

				vmovups ymm0, ymmword ptr[rcx + rsi * 4]
				vmovups ymm1, ymmword ptr [rcx + rdi * 4]

				vmovups ymmword ptr [rcx + rsi * 4], ymm1
				vmovups ymmword ptr [rcx + rdi * 4], ymm0

				add rsi, ymmFloats
				add rdi, ymmFloats
				dec r10
				jmp _avxSwap

			
			_simpleSwap:
				test r11, r11
				jz _pivot_normalization

				movss xmm0, dword ptr [rcx + rsi * 4]
				movss xmm1, dword ptr [rcx + rdi * 4]

				movss dword ptr [rcx + rsi * 4], xmm1
				movss dword ptr [rcx + rdi * 4], xmm0

				inc rsi
				inc rdi
				dec r11	
				jmp _simpleSwap


	_pivot_normalization:
	
		mov rsi, r14	; RSI = currentPivotOffset	

		mov r10, r8		; R10 = iterations with AVX normalization
		sub r10, r13
		mov r11, r10	; R11 = iterations of simplenormalization
		shr r10, 3		
		and r11, 7

		movss xmm0, dword ptr [rcx + r14 * floatSize] ; XMM0 = current pivot value

		vbroadcastss ymm0, xmm0 ; YMM0 vector of pivot values

		_avxNormalization:
			test r10, r10
			jz _simpleNormalization

			vmovups ymm1, ymmword ptr [rcx + rsi * 4]
			vdivps ymm1, ymm1, ymm0
			vmovups ymmword ptr [rcx + rsi * 4], ymm1
			
			add rsi, ymmFloats
			dec r10
			jmp _avxNormalization

		_simpleNormalization:
			test r11, r11
			jz _elimination
			
			movss xmm1, dword ptr [rcx + rsi * 4]
			divss xmm1, xmm0
			movss dword ptr [rcx + rsi * 4], xmm1

			inc rsi
			dec r11
			jmp _simpleNormalization

_elimination:
	push rcx
	push rdx
	push r8


	mov pivotRowIdx, r13
	mov DWORD PTR[threadData + startRowOff],	0
	mov DWORD PTR[threadData + endRowOff],		r15d

	lea rcx, [threadData]

	call eliminate_on_thread

	pop r8
	pop rdx
	pop rcx

	inc r13					; ++curr_row
	jmp _solveLoopStart		; _equatiosIteration loop


_solveLoopEnd:
	; RCX = float* matrix_ptr
	; RDX = num_rows
	; R8 = num_cols
	mov rcx, matrixAddr
	mov rdx, numRows
	mov r8, numCols
	call remove_close_zeros

	mov rcx, matrixAddr
	mov rdx, numRows
	mov r8, numCols
	call has_solutions

	pop rdi
	pop rsi
	pop r15
	pop r14
	pop r13
	pop r12
	ret
solve_linear_system ENDP
; <------------------------------------------------------->



; <------------------------------------------------------->
; PROCEDURE remove_close_zeros
; Changes numbers that are close to 0.0 to 0.0.
remove_close_zeros PROC
	; RCX = float* matrix_ptr
	; RDX = num_rows
	; R8 = num_cols

	mov rax, r8
	dec rax
	imul rdx, r8
_removingZerosStart:
	cmp rax, rdx
	jge _removingZerosFinish

	movss xmm0, dword ptr [rcx + rax * floatSize]

	is_zero xmm0
	ja _removingZerosItNext
	movss xmm1, dword ptr [zeroVal]
	movss dword ptr [rcx + rax * floatSize], xmm1

_removingZerosItNext:
	add rax, r8
	jmp _removingZerosStart

_removingZerosFinish:
	ret
remove_close_zeros ENDP
; <------------------------------------------------------->



; <------------------------------------------------------->
; PROCEDURE has_solutions
; If solved matrix has solutions returns 1 in RAX else returns 0.
has_solutions PROC
	; RCX = float* matrix_ptr
	; RDX = num_rows
	; R8 = num_cols

	dec rdx ; iterate from end, start from num_rows - 1

	mov r9, r8	; R9 = numVariables
	dec r9

	xor rax, rax ; RAX = currElOffset (we are starting from the first one)

_checkingSolutionsStart:
	cmp rdx, 0	; if (rowIdx < 0) break
	jl _checkingSolutionsEnd

	mov r10, 1 ; R10 = allZeros
	xor r11, r11 ; R11 = columnIdx

	_chkSolutionColumnIt:
		cmp r11, r9
		jge _chkSolutionColumnEnd

		movss xmm0, dword ptr [rcx + rax * floatSize]

		is_zero xmm0
		jbe _checkedIsZero

		cmp r10, 1		; if (allZeros == false)
		je _notAllZeros ;	allZeros = false
		xor rax, rax	; else
		ret				;	return false

		_notAllZeros:
			xor r10, r10; allZeros = false

		_checkedIsZero:
			inc rax		; move to next element
			inc r11		; iterate to next column
			jmp _chkSolutionColumnIt
	_chkSolutionColumnEnd:

	test r10, r10				; if (allZeros == false)
	jz _checkingSolutionsItEnd	;	continue

	movss xmm0, dword ptr [rcx + rax * floatSize]
	is_zero xmm0				; if (xmm0 == 0.0)
	jbe _checkingSolutionsItEnd	;	continue

	xor rax, rax			; else
	ret						; return false

_checkingSolutionsItEnd:
	inc rax
	dec rdx
	jmp _checkingSolutionsStart

_checkingSolutionsEnd:
	mov rax, 1	; return true
	ret
has_solutions ENDP
; <------------------------------------------------------->

END