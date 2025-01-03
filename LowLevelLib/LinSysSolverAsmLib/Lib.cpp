#include <windows.h>
#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include "Lib.h"

#define EPSILON fabs(1e-9)

// OK
static inline bool is_zero(double arg)
{
    return fabs(arg) < EPSILON;
}

// OK
static inline double* at(double* matrix, int sizeX, int row, int col)
{
    return &matrix[sizeX * row + col];
}


static inline double val_at(double* matrix, int sizeX, int row, int col)
{
    return matrix[sizeX * row + col];
}


static inline int first_non_zero_in_col(double* matrix, int sizeX, int sizeY, int col, int startRow)
{
    for (int row = startRow; row < sizeY; row++)
    {
        double el = val_at(matrix, sizeX, row, col);
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
        double temp = val_at(matrix, sizeX, rowA, col);
        *at(matrix, sizeX, rowA, col) = val_at(matrix, sizeX, rowB, col);
        *at(matrix, sizeX, rowB, col) = temp;
    }
}


static bool is_solvable(double* matrix, int rows, int cols)
{
    int var_num = cols - 1;

    for (int rowIdx = 0; rowIdx < rows; rowIdx++)
    {
        bool all_zeros = true;
        for (int c = 0; c < var_num; c++)
        {
            double val = val_at(matrix, cols, rowIdx, c);
            if (!is_zero(val))
            {
                if (!all_zeros)
                {
                    return false;
                }

                all_zeros = false;
            }
        }

        double solution = val_at(matrix, cols, rowIdx, var_num);
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
        double val = val_at(matrix, cols, rowIdx, i);
        if (!is_zero(val))
        {
            return false;
        }
    }

    return true;
}

#define NO_SOLUTIONS 0
#define ONE_SOLUTION 1
#define INFINITE_SOLUTIONS 2

static int solutions_in_system(double* matrix, int rows, int cols)
{
    int variables_num = cols - 1;

    if (!is_solvable(matrix, rows, cols))
    {
        return variables_num > rows ? INFINITE_SOLUTIONS : NO_SOLUTIONS;
    }

    for (int row = 0; row < variables_num; row++)
    {
        if (row_contains_only_zeros(matrix, cols, row))
        {
            return INFINITE_SOLUTIONS;
        }
    }

    return ONE_SOLUTION;
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

        double factor = val_at(matrix, cols, r, pivotColIdx);
        if (is_zero(factor))
        {
            continue;
        }

        for (int c = pivotColIdx; c < cols; c++)
        {
            double valPivotRow = val_at(matrix, cols, pivotRowIdx, c);
            *at(matrix, cols, r, c) -= factor * valPivotRow;
        }
    }
}

typedef struct {
    double* matrix;
    int cols;
    int pivot_row_idx;
    int startRow;
    int endRow;
} GaussJordanThreadData;

static DWORD WINAPI rows_op_thread(LPVOID lpParam)
{
    GaussJordanThreadData* data = (GaussJordanThreadData*)lpParam;
    double* matrix = data->matrix;
    int cols = data->cols;
    int pivot_row_idx = data->pivot_row_idx;
    int startRow = data->startRow;
    int endRow = data->endRow;

    int pivot_col_idx = pivot_row_idx;

    for (int r = startRow; r < endRow; r++)
    {
        if (r == pivot_row_idx) {
            continue;
        }

        double factor = val_at(matrix, cols, r, pivot_col_idx);
        if (is_zero(factor)) {
            continue;
        }

        for (int c = pivot_col_idx; c < cols; c++)
        {
            double val_pivot_row = val_at(matrix, cols, pivot_row_idx, c);
            *at(matrix, cols, r, c) -= factor * val_pivot_row;
        }
    }

    return 0;
}

static void eliminate_multi_thread(double* matrix, int rows, int cols, int pivor_row_idx, int num_threads)
{
#define MAX_THREADS 64
    num_threads = min(MAX_THREADS, num_threads);
    HANDLE threads[MAX_THREADS];
    GaussJordanThreadData threadData[MAX_THREADS];

    int rows_per_thread = rows / num_threads;
    int start = 0;

    for (int i = 0; i < num_threads; i++)
    {
        int end = (i == num_threads - 1) ? rows : (start + rows_per_thread);

        threadData[i].matrix = matrix;
        threadData[i].cols = cols;
        threadData[i].pivot_row_idx = pivor_row_idx;
        threadData[i].startRow = start;
        threadData[i].endRow = end;

        threads[i] = CreateThread(NULL, 0, rows_op_thread, &threadData[i], 0, NULL);

        if (threads[i] == NULL) {
            fprintf(stderr, "Failed to create thread %d\n", i);
            return;
        }

        start = end;
    }

    WaitForMultipleObjects(num_threads, threads, TRUE, INFINITE);

    for (int i = 0; i < num_threads; i++)
    {
        CloseHandle(threads[i]);
    }
}

// Solves in-place system of linear equations.
// Returns:
//  - 0: system has no solution,
//  - 1: system has 1 solution,
//  - 2: system has infinite number of solutions,
int solve_linear_system(double* matrix, int rows, int cols, int num_threads)
{
    int variables_num = cols - 1;           // OK
    int it_num = min(variables_num, rows);  // OK
    for (int row = 0; row < it_num; row++)  // OK
    {
        double pivot = *at(matrix, cols, row, row); // OK

        if (is_zero(pivot)) // OK
        {
            int foundRow = first_non_zero_in_col(matrix, cols, rows, row, row + 1); // ok
            if (foundRow == -1) // ok
            {
                continue;
            }

            swap_rows(matrix, cols, row, foundRow, row); // ok
            pivot = val_at(matrix, cols, row, row); // ok
        }

        // Normalize pivot row.
        for (int c = row; c < cols; c++) // ok
        {
            *at(matrix, cols, row, c) /= pivot;
        }

        // could take out loop for better performance
        if (num_threads ==  1)
        {
            eliminate_single_thread(matrix, rows, cols, row);
        }
        else
        {
            eliminate_multi_thread(matrix, rows, cols, row, num_threads);
        }
    }

    // remove minus zeros from result column
    int solution_col = cols - 1;
    for (int i = 0; i < rows; i++)
    {
        double* val_ptr = at(matrix, cols, i, solution_col);
        if (is_zero(*val_ptr))
        {
            *val_ptr = 0.0;
        }
    }

    return solutions_in_system(matrix, rows, cols);
}