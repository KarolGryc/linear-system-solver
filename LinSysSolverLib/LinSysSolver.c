#include <windows.h>
#include <math.h>
#include <stdbool.h>

#define EPSILON fabs(1e-9)


static inline bool is_zero(double arg)
{
    return fabs(arg) < EPSILON;
}


static inline double* at(double* matrix, int sizeX, int row, int col)
{
    return &matrix[sizeX * row + col];
}


static inline int first_non_zero_in_col(double* matrix, int sizeX, int sizeY, int col, int startRow)
{
    for (int row = startRow; row < sizeY; row++)
    {
        double el = *at(matrix, sizeX, row, col);
        if (!is_zero(el)) 
        {
            return row;
        }
    }

    return -1;
}


static inline void swap_rows(double* matrix, int sizeX, int rowA, int rowB, int startCol)
{
    for (int col = startCol; col < sizeX; col++)
    {
        double temp = *at(matrix, sizeX, rowA, col);
        *at(matrix, sizeX, rowA, col) = *at(matrix, sizeX, rowB, col);
        *at(matrix, sizeX, rowB, col) = temp;
    }
}


static bool has_solutions(double* matrix, int rows, int cols)
{
    int var_num = cols - 1;

    for (int rowIdx = 0; rowIdx < rows; rowIdx++)
    {
        bool all_zeros = true;
        for (int c = 0; c < var_num; c++)
        {
            double val = *at(matrix, cols, rowIdx, c);
            if (!is_zero(val))
            {
                if (!all_zeros)
                {
                    return false;
                }

                all_zeros = false;
            }
        }

        double solution = *at(matrix, cols, rowIdx, var_num);
        if (all_zeros && !is_zero(solution))
        {
            return false;
        }
    }

    return true;
}

static inline bool row_contains_only_zeros(double* matrix, int cols, int rowIdx)
{
    for (int i = 0; i < cols; i++)
    {
        double val = *at(matrix, cols, rowIdx, i);
        if (!is_zero(val))
        {
            return false;
        }
    }

    return true;
}

static int solutions_in_system(double* matrix, int rows, int cols)
{
    if (!has_solutions(matrix, rows, cols))
    {
        return 0;
    }

    int variables_num = cols - 1;
    for (int row = 0; row < variables_num; row++)
    {
        if (row_contains_only_zeros(matrix, cols, row))
        {
            return 2;
        }
    }

    return 1;
}


static void eliminate_single_thread(double* matrix, int rows, int cols, int pivotRowIdx)
{
    int pivotColIdx = pivotRowIdx;
    for (int r = 0; r < rows; r++)
    {
        if (r == pivotRowIdx)
        {
            continue;
        }

        double factor = *at(matrix, cols, r, pivotColIdx);
        if (is_zero(factor))
        {
            continue;
        }

        for (int c = pivotColIdx; c < cols; c++)
        {
            double valPivotRow = *at(matrix, cols, pivotRowIdx, c);
            *at(matrix, cols, r, c) -= factor * valPivotRow;
        }
    }
}


// Solves in-place system of linear equations.
// Returns:
//  - 0: system has no solution,
//  - 1: system has 1 solution,
//  - 2: system has infinite number of solutions,
__declspec(dllexport)
int solve_linear_system(double* matrix, int rows, int cols)
{
    int variables_num = cols - 1;

    if (variables_num < rows) {

    }

    for (int row = 0; row < variables_num; row++)
    {
        double pivot = *at(matrix, cols, row, row);

        if (is_zero(pivot))
        {
            int foundRow = first_non_zero_in_col(matrix, cols, rows, row, row + 1);
            if (foundRow == -1)
            {
                continue;
            }

            swap_rows(matrix, cols, row, foundRow, row);
            pivot = *at(matrix, cols, row, row);
        }

        // Normalize pivot row.
        for (int c = row; c < cols; c++)
        {
            *at(matrix, cols, row, c) /= pivot;
        }

        eliminate_single_thread(matrix, rows, cols, row);
    }

    return solutions_in_system(matrix, rows, cols);
}