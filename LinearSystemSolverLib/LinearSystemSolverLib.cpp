#include "pch.h"
#include "LinearSystemSolverLib.h"
#include <math.h>
#include <limits.h>
#include <iostream>

inline double* at(double* matrix, unsigned rowSize, unsigned row, unsigned col)
{
	std::cout << "Calling at: " << row << " " << col << std::endl;
	return &matrix[rowSize * row + col];
}

inline unsigned minValue(unsigned x, unsigned y) {
	return (x < y) ? x : y;
}

void swap_rows(double* matrix, unsigned rowSize, unsigned idxRowA, unsigned idxRowB)
{
	std::cout << "Calling swap rows " << idxRowA << " " << idxRowB << std::endl;
	for (unsigned i = 0; i < rowSize; i++) {
		double* elemA = at(matrix, rowSize, idxRowA, i);
		double* elemB = at(matrix, rowSize, idxRowA, i);
		double tmp = *elemA;
		*elemA = *elemB;
		*elemB = *elemA;
	}
}


unsigned first_non_zero_elem_row(double* matrix, unsigned sizeX, unsigned sizeY, unsigned columnIdx, unsigned startIdx = 0)
{
	std::cout << "Calling find on col: " << columnIdx << " starting from: " << startIdx << std::endl;
	for (unsigned i = startIdx; i < sizeX; i++) {
		double* el = at(matrix, sizeX, i, columnIdx);
		if (*el != 0) {
			return i;
		}
	}

	return UINT_MAX;
}


void divide_row(double* matrix, unsigned sizeX, unsigned rowIdx, const double dividend, unsigned startCol, unsigned endCol)
{
	std::cout << "Calling divide row idx: " << rowIdx << " divide by: " 
		<< dividend << " start col:" << startCol << std::endl;
	unsigned endColIdx = minValue(sizeX - 1, endCol);
	for (unsigned i = startCol; i <= endCol; i++) {
		double* el = at(matrix, sizeX, rowIdx, i);
		*el /= dividend;
	}
}


void subtractRow(double* matrix, unsigned sizeX, unsigned sizeY, unsigned minuendRowIdx, unsigned subtrahendRowIdx, unsigned startColIdx)
{
	std::cout << "Calling sub row " << minuendRowIdx << " - " 
		<< subtrahendRowIdx<< " start col:" << startColIdx << std::endl;
	for (int i = startColIdx; i < sizeX; i++) {
		double* minuend = at(matrix, sizeX, minuendRowIdx, i);
		double* subtrahend = at(matrix, sizeX, subtrahendRowIdx, i);
		*minuend -= *subtrahend;
	}
}


void solve_matrix_equation_system(double* matrix, unsigned sizeX, unsigned sizeY)
{
	for (int i = 0; i < sizeX - 1; ++i) {
		double* first = at(matrix, sizeX, i, i);
		if (*first == 0) {
			unsigned nonZeroElIdx = first_non_zero_elem_row(matrix, sizeX, sizeY, i, i);
			if (nonZeroElIdx != UINT_MAX) {
				swap_rows(matrix, sizeX, i, nonZeroElIdx);
			}
			else {
				// throw error or something in C-style?
			}
		}

		divide_row(matrix, sizeX, i, *first, i, sizeX);

		for (int row = 0; row < sizeY; row++) {
			if (row != i) {
				double factor = *at(matrix, sizeX, row, i);
				for (int col = i; col < sizeX; col++) {
					*at(matrix, sizeX, row, col) -= factor * *at(matrix, sizeX, i, col);
				}
			}
		}
	}
}