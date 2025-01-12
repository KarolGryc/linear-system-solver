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
	oneVal			dd 1.0
	maxThreads		dq MAX_THREADS
	rmSignMask		dd 07FFFFFFFh
	flipSignMask	dd 080000000h
	floatSize		EQU 4
	ymmFloats		EQU 8
	ymmSize			EQU floatSize * ymmFloats
	intSize			EQU 4
	handleSize		EQU 8 
	
	; GaussJordanThreadData STRUCT offsets
	startRowOff		EQU	0
	endRowOff		EQU 8

.data 
	matrixAddr	dq	0
	numCols		dq	0
	numRows		dq	0
	numThreads	dq	1
	pivotRowIdx dq	0
    threadHandles   dq MAX_THREADS DUP(66)
    threadData      GaussJordanThreadData MAX_THREADS DUP(<51, 51>)

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
	; preparing registers
	push rsi
												; RCX <-> threadDataPtr
	mov	rdx,	matrixAddr						; RDX = float* matrix
	mov	r8,		numCols							; R8  = int cols (rowSize)
	mov	r9,		pivotRowIdx						; R9  = int pivotRowIdx (pivotColIdx)
	mov	r10,	QWORD PTR [rcx + startRowOff]	; R10 = int startRowIdx (currRow)
	mov	r11,	QWORD PTR [rcx + endRowOff]		; R11 = int endRowIdx
	movss xmm4, flipSignMask					; load flipping sign mask

_elimStart:
	cmp r10, r11	; if (currRow >= endRowIdx)
	jge _finishElim ;	break

	cmp r10, r9		; if (currRow == pivotRow)
	je _endLoop		;	continue	(skip row)

	mtx_off rax, r8, r10, r9 ; factor = value at (currRow, pivotColIdx)

	movss xmm5, DWORD PTR [rdx + rax * floatSize] ; load factor to XMM0

	; For maximum performance we should skip if factor == 0
	; For ease of testing AVX performance we skip this step

	xorps xmm5, xmm4			; flip the sign of xmm5 to use vfmadd231ps
	vbroadcastss ymm4, xmm5		; spread the -factor to ymm4
								
	mov rcx, r8					; RCX = columns to eliminate
	sub rcx, r9

	mtx_off rsi, r8, r9, r9 	; load pivot first element offset
	_elimLoopAvx:
		cmp rcx, ymmFloats * 2	; If there are not enough elements for AVX
		jl _elimLoopNormal		; Eliminate tail without AVX

		vmovups ymm2, ymmword ptr [rdx + rax * floatSize]			; load destiny
		vmovups ymm0, ymmword ptr [rdx + rax * floatSize + ymmSize]	; load destiny + 64B
		vmovups ymm3, ymmword ptr [rdx + rsi * floatSize]			; load pivot
		vmovups ymm1, ymmword ptr [rdx + rsi * floatSize + ymmSize]	; load pivot   + 64B

		vfmadd231ps ymm2, ymm3, ymm4	; destiny += -factor * pivot
		vfmadd231ps ymm0, ymm1, ymm4

		vmovups ymmword ptr [rdx + rax * floatSize], ymm2			; store destiny
		vmovups ymmword ptr [rdx + rax * floatSize + ymmSize], ymm0	; store destiny + 64B

		add rsi, ymmFloats * 2	; move to next elements in pivot and destiny
		add rax, ymmFloats * 2
		sub rcx, ymmFloats * 2	; reduce number of elements left
		jmp _elimLoopAvx		

	_elimLoopNormal:
		test rcx, rcx		; perform if there are elements left
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
	inc r10			; increment row
	jmp _elimStart	;

_finishElim:
	pop rsi			; returning values of registers
	xor rax, rax	; return 0
	ret
eliminate_on_thread ENDP
; <------------------------------------------------------->




; <------------------------------------------------------->
; PROCEDURE eliminate_multithread
; Does elimination with multiple threads
eliminate_multithread MACRO
	push r12
	push r13
	push r14
	push r15
	push rsi
	push rdi
	
	; create threads
	mov rax, numRows	; RAX = numRows
	xor rdx, rdx
	mov r12, numThreads ; R12 = numThreads
    div r12
	mov r14, rax		; R14 = rows_per_thread

	xor r11, r11		; R11 = range start
	mov r13, rdx		; R13 = endRow (first row has +remainder rows)
	xor r15, r15		; R15 = loopIt = 0
	mov rsi, offset threadData
	mov rdi, offset threadHandles

_threadCreateLoop:
	cmp r15, r12		; while (currThread < numThreads)
	jge _threadCreateLoopEnd

	add r13, r14		; endRow = startRow + rowsPerThread

	mov qword ptr [rsi], r11		; fill thread data
	mov qword ptr [rsi + 8], r13

	sub rsp, 30h					; stack preparation
	xor rax, rax
	mov [rsp+28h], rax				; dwCreationFlags = 0
	mov [rsp+20h], rax				; lpThreadId = NULL
	mov r9, rsi						; lpParameter = currentThreadData
	lea r8, [eliminate_on_thread]	; lpStartAddress = executedProcedureAddress
	xor rdx, rdx					; dwStackSize = 0 (default)
	xor rcx, rcx					; lpThreadAttributes = 0
	call CreateThread	; CreateThread(NULL, 0, rows_op_thread, &threadData[i], 0, NULL)
	add rsp, 30h

	mov qword ptr [rdi + r15 * handleSize], rax ; rax contains handle

	add rsi, sizeof GaussJordanThreadData		; move to next data structure
	mov r11, r13		; start = end
	inc r15				; ++loopIt
	jmp _threadCreateLoop

_threadCreateLoopEnd:
	
	; wait for threads
	sub rsp, 20h ; WaitForMultipleObjects(num_threads, threads, TRUE, INFINITE);
	mov rcx, r12
	mov rdx, offset threadHandles
	mov r8, 1
	mov r9, 0FFFFFFFFh
	call WaitForMultipleObjects
	add rsp, 20h

	; close threads
	xor r15, r15			; R15 = closed thread index
_closeThreadLoop:
	cmp r15, r12			; while (closed_thread_idx < num_threads)
	jge _closeThreadLoopEnd

	sub rsp, 20h	; CloseHandle(threadHandles[r15])
	mov rcx, qword ptr[rdi + r15 * handleSize]
	call CloseHandle
	add rsp, 20h

	inc r15
	jmp _closeThreadLoop

_closeThreadLoopEnd:
	
	pop rdi
	pop rsi
	pop r15
	pop r14
	pop r13
	pop r12
ENDM
; <------------------------------------------------------->



; <------------------------------------------------------->
; MACRO prepare_thread_array
; Prepares global variables for execution
prepare_thread_array MACRO mtxAddr, nRows, nCols, nThreads
	mov rax, nThreads
	write_min rax, qword ptr [maxThreads]
	mov numThreads, rax
	mov matrixAddr, mtxAddr
	mov numCols, nCols
	mov numRows, nRows
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
	push r12	; save registers on stack
	push r13
	push r14
	push r15
	push rsi
	push rdi
	push rbx

	prepare_thread_array rcx, rdx, r8, r9	; save matrix data in variables

	mov rbx, rcx				; RBX = matrix_address
	mov r15, rdx				; R15 = num_of_rows
	mov r12, r8					; R12 = num_of_iterations
	dec r12						; variables_num = cols - 1
	write_min r12, r15			; num_of_iterations = min(rows, variables_num)

	xor r13, r13				; R13 = curr_row

_solveLoopStart:
	cmp r13, r12		; if(curr_row >= possible_iterations)
	jge	_solveLoopEnd	; end the loop

	mtx_off r14, r8, r13, r13	; R14 = curr_pivot_element_offset
								; pivot_el_row == pivot_el_col
	
	movss xmm0, dword ptr [rbx + r14 * floatSize] ; XMM0 = pivot_val

	is_zero xmm0				; if (pivot_val == 0.0) swap rows
	jnbe _pivot_normalization	; else goto normalization

_pivot_is_zero:
	mov rdx, r13	; RDX = it_row iterator for searching non zero		
	inc rdx			; it_row = curr_row + 1	
	mtx_off r10, r8, rdx, r13 						; get element offset into r10

	_itStart:
		cmp rdx, r15	; if(it_row >= rowsNum)
		jge _notFound	;	jump to not found

		movss xmm0, dword ptr [rbx + r10 * floatSize]	; move element value into xmm0
		
		is_zero xmm0 ; if (xmm0 == 0.0)
		jnbe _found	 ;	jump to swap_rows

		add r10, r8
		inc rdx		 ; else
		jmp _itStart ;	check next row

	_notFound:
		inc r13				
		jmp _solveLoopStart	; skip iteration (probably should end with no solutions?)

	_found:	; swap rows
		mov rsi, r14 ; RSI = element A to swap ptr
		mov rdi, r10 ; RDI = element B to swap ptr

		mov r10, r8
		sub r10, r13 ; R10 - R13 = elements left in row
		mov r11, r10
		shr r10, 3	; R10 = iterations with AVX
		and r11, 7 ; R11 = iterations of simple swap

		_avxSwap:
			test r10, r10
			jz _simpleSwap

			vmovups ymm0, ymmword ptr[rbx + rsi * floatSize]	; load row A
			vmovups ymm1, ymmword ptr [rbx + rdi * floatSize]	; load row B

			vmovups ymmword ptr [rbx + rsi * floatSize], ymm1	; save row B to A
			vmovups ymmword ptr [rbx + rdi * floatSize], ymm0	; save row A to B

			add rsi, ymmFloats	; move to next elements A
			add rdi, ymmFloats	; move to next elements B
			dec r10				; reduce iterations left
			jmp _avxSwap

			
		_simpleSwap:
			test r11, r11
			jz _pivot_normalization

			movss xmm0, dword ptr [rbx + rsi * floatSize]	; load el A
			movss xmm1, dword ptr [rbx + rdi * floatSize]	; load el B

			movss dword ptr [rbx + rsi * floatSize], xmm1	; save el B to A
			movss dword ptr [rbx + rdi * floatSize], xmm0	; save el A to B

			inc rsi	; move to next element A
			inc rdi	; move to next element B
			dec r11	; reduce iterations left
			jmp _simpleSwap


_pivot_normalization:
	
	mov rsi, r14	; RSI = currentPivotOffset	
	mov r10, r8		; R10 = iterations with AVX normalization
	sub r10, r13
	mov r11, r10	; R11 = iterations of simple normalization
	shr r10, 3		
	and r11, 7

	movss xmm0, dword ptr [rbx + r14 * floatSize] ; XMM0 = current pivot value

	vbroadcastss ymm0, xmm0 ; YMM0 vector of pivot values

	_avxNormalization:
		test r10, r10
		jz _simpleNormalization

		vmovups ymm1, ymmword ptr [rbx + rsi * floatSize]	; load 8 elements
		vdivps ymm1, ymm1, ymm0								; normalize
		vmovups ymmword ptr [rbx + rsi * floatSize], ymm1	; load back
			
		add rsi, ymmFloats	; move to next elements
		dec r10				; reduce iterations left
		jmp _avxNormalization

	_simpleNormalization:
		test r11, r11
		jz _elimination
			
		movss xmm1, dword ptr [rbx + rsi * floatSize]		; load element 
		divss xmm1, xmm0									; normalize
		movss dword ptr [rbx + rsi * floatSize], xmm1		; load back

		inc rsi				; move to next element
		dec r11				; reduce iterations left
		jmp _simpleNormalization

_elimination:
	push r8					; save rowSize

	mov pivotRowIdx, r13	; set global current pivot row
	eliminate_multithread	; eliminate using multi-threading
	
	pop r8
	inc r13					; ++curr_row
	jmp _solveLoopStart		; _equatiosIteration loop


_solveLoopEnd:
	mov rcx, matrixAddr		; change solutions ~0.0 to =0.0
	mov rdx, numRows
	mov r8, numCols
	call remove_close_zeros

	mov rcx, matrixAddr		; get number of solutions
	mov rdx, numRows
	mov r8, numCols
	call number_of_solutions

	pop rbx ; retrieve registers
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
; RCX = float* matrix_ptr
; RDX = num_rows
; R8 = num_cols
remove_close_zeros PROC
	mov rax, r8		; RAX = last_column_idx (first row)
	dec rax			; last_column_idx = num_cols - 1
	imul rdx, r8	; RDX = num_of_elements (num_rows * num_cols)

	movss xmm0, dword ptr [zeroVal]	; XMM0 = zeroVal

_removingZerosStart:
	cmp rax, rdx
	jge _removingZerosFinish

	movss xmm2, dword ptr [rcx + rax * floatSize]

	is_zero xmm2			; if (is_zero(XMM2)) set 0.0
	ja _removingZerosNextIt ; else continue
	movss dword ptr [rcx + rax * floatSize], xmm0

_removingZerosNextIt:
	add rax, r8		; move last_column_idx to next element
	jmp _removingZerosStart

_removingZerosFinish:
	ret
remove_close_zeros ENDP
; <------------------------------------------------------->


; <------------------------------------------------------->
; PROCEDURE solutions_in_system
; Gives number of solutions in solver linear system.
; RCX = float* matrix_ptr
; RDX = num_rows
; R8 = num_cols
solutions_in_system PROC
    ; Constants
    NO_SOLUTIONS        equ 0
    ONE_SOLUTION        equ 1
    INFINITE_SOLUTIONS  equ 2

	push r12				; store registers
	push r13

    mov r9, r8				; R9 = variables_num
    dec r9                  ; variables_num = cols - 1
    xor r10, r10			; R10 = rank = 0
    xor r11, r11			; R11 = row = 0

_loopRows:
	cmp r11, rdx            ; if (curr_row >= num_rows)
	jge _checkRank          ;     goto CheckRank

	xor r12, r12            ; R12 = curr_col = 0
	xor rax, rax			; RAX = non_zero_found = false

	mtx_off r13, r8, r11, 0
	_checkColumns:
		cmp r12, r9			; while (curr_col < num_of_variables) 
		jge _endCheckCols

		movss xmm0, dword ptr [rcx + r13 * floatSize]
		is_zero xmm0
		jbe _nextItCheckColumns

		mov rax, 1
		inc r10
		jmp _enchCheckCols

	_nextItCheckColumns:
		inc r12
		inc r13
		jmp _checkColumns
	_endCheckCols:


_checkRank:
    cmp r10, r9               ; if rank < num_of_variables
    jl InfiniteSolutions      ;     return INFINITE_SOLUTIONS

_oneSolution:
    mov eax, ONE_SOLUTION     ; return ONE_SOLUTION
    jmp _returnSolutions

_noSolutions:
    mov eax, NO_SOLUTIONS     ; return NO_SOLUTIONS
    jmp _returnSolutions

_infiniteSolutions:
    mov eax, INFINITE_SOLUTIONS ; return INFINITE_SOLUTIONS

_returnSolutions:
	pop r13
	pop r12
    ret
solutions_in_system ENDP
; <------------------------------------------------------->

END