#include <windows.h>
#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdint.h>

#define EPSILON 1e-9f
#define NO_SOLUTIONS 0
#define ONE_SOLUTION 1
#define INFINITE_SOLUTIONS 2

static inline bool is_zero(float arg)
{
    return fabsf(arg) < EPSILON;
}


static inline float* at(float* matrix, int64_t sizeX, int64_t row, int64_t col)
{
    return &matrix[sizeX * row + col];
}


static inline float val_at(float* matrix, int64_t sizeX, int64_t row, int64_t col)
{
    return matrix[sizeX * row + col];
}


static inline int64_t first_non_zero_in_col(float* matrix, int64_t sizeX, int64_t sizeY, int64_t col, int64_t startRow)
{
    for (int64_t row = startRow; row < sizeY; row++)
    {
        float el = val_at(matrix, sizeX, row, col);
        if (!is_zero(el))
        {
            return row;
        }
    }

    return -1ll;
}


static inline void swap_rows(float* matrix, int64_t sizeX, int64_t rowA, int64_t rowB, int64_t startCol)
{
    for (int64_t col = startCol; col < sizeX; col++)
    {
        float temp = val_at(matrix, sizeX, rowA, col);
        *at(matrix, sizeX, rowA, col) = val_at(matrix, sizeX, rowB, col);
        *at(matrix, sizeX, rowB, col) = temp;
    }
}


static int64_t solutions_in_system(float* matrix, int64_t rows, int64_t cols)
{
    int64_t rank = 0;
    int64_t num_of_variables = cols - 1;

    for (int64_t row = 0; row < rows; row++) 
    {
        bool non_zero_found = false;
        for (int64_t col = 0; col < num_of_variables; col++) 
        {
            float val = val_at(matrix, cols, row, col);
            if (!is_zero(val)) 
            {
                non_zero_found = true;
                rank++;
                break;
            }
        }

        float solution_val = val_at(matrix, cols, row, num_of_variables);
        if (!non_zero_found && !is_zero(solution_val))
        {
            return NO_SOLUTIONS; 
        }
    }

    if (rank < num_of_variables)
    {
        return INFINITE_SOLUTIONS;
    }

    return ONE_SOLUTION;
}


static void eliminate_single_thread(float* matrix, int64_t rows, int64_t cols, int64_t pivotRowIdx)
{
    int64_t pivotColIdx = pivotRowIdx;
    for (int64_t r = 0; r < rows; r++)
    {
        if (r == pivotRowIdx)
        {
            continue;
        }

        float factor = val_at(matrix, cols, r, pivotColIdx);
        if (is_zero(factor))
        {
            continue;
        }

        for (int64_t c = pivotColIdx; c < cols; c++)
        {
            float valPivotRow = val_at(matrix, cols, pivotRowIdx, c);
            *at(matrix, cols, r, c) -= factor * valPivotRow;
        }
    }
}

typedef struct {
    float* matrix;
    int64_t cols;
    int64_t pivot_row_idx;
    int64_t startRow;
    int64_t endRow;
} GaussJordanThreadData;


static DWORD WINAPI rows_op_thread(LPVOID lpParam)
{
    GaussJordanThreadData* data = (GaussJordanThreadData*)lpParam;
    float* matrix = data->matrix;
    int64_t cols = data->cols;
    int64_t pivot_row_idx = data->pivot_row_idx;
    int64_t startRow = data->startRow;
    int64_t endRow = data->endRow;

    int64_t pivot_col_idx = pivot_row_idx;

    for (int64_t r = startRow; r < endRow; r++)
    {
        if (r == pivot_row_idx) {
            continue;
        }

        float factor = val_at(matrix, cols, r, pivot_col_idx);
        
        // For maximum performance we should skip if factor == 0
        // For ease of testing AVX performance we skip this step
        //if (is_zero(factor)) {
        //    continue;
        //}

        for (int64_t c = pivot_col_idx; c < cols; c++)
        {
            float val_pivot_row = val_at(matrix, cols, pivot_row_idx, c);
            *at(matrix, cols, r, c) -= factor * val_pivot_row;
        }
    }

    return 0;
}


static void eliminate_multi_thread(float* matrix, int64_t rows, int64_t cols, int64_t pivor_row_idx, int64_t num_threads)
{
#define MAX_THREADS 64
    num_threads = min(MAX_THREADS, num_threads);
    HANDLE threads[MAX_THREADS];
    GaussJordanThreadData threadData[MAX_THREADS];

    int64_t rows_per_thread = rows / num_threads;
    int64_t start = 0;

    for (int64_t i = 0; i < num_threads; i++)
    {
        int64_t end = (i == num_threads - 1) ? rows : (start + rows_per_thread);

        threadData[i].matrix = matrix;
        threadData[i].cols = cols;
        threadData[i].pivot_row_idx = pivor_row_idx;
        threadData[i].startRow = start;
        threadData[i].endRow = end;

        threads[i] = CreateThread(NULL, 0, rows_op_thread, &threadData[i], 0, NULL);

        if (threads[i] == NULL) {
            printf("Failed to create thread %d\n", i);
            return;
        }

        start = end;
    }

    WaitForMultipleObjects(num_threads, threads, TRUE, INFINITE);

    for (int64_t i = 0; i < num_threads; i++)
    {
        CloseHandle(threads[i]);
    }
}


// Solves in-place system of linear equations.
// Returns:
//  - 0: system has no solution,
//  - 1: system has 1 solution,
//  - 2: system has infinite number of solutions,
__declspec(dllexport)
int64_t solve_linear_system(float* matrix, int64_t rows, int64_t cols, int64_t num_threads)
{

    int64_t variables_num = cols - 1;
    int64_t it_num = min(variables_num, rows);
    for (int64_t row = 0; row < it_num; row++)
    {
        float pivot = *at(matrix, cols, row, row);

        if (is_zero(pivot))
        {
            int64_t foundRow = first_non_zero_in_col(matrix, cols, rows, row, row + 1);
            if (foundRow == -1)
            {
                continue;
            }

            swap_rows(matrix, cols, row, foundRow, row);
            pivot = val_at(matrix, cols, row, row);
        }

        // Normalize pivot row.
        for (int64_t c = row; c < cols; c++)
        {
            *at(matrix, cols, row, c) /= pivot;
        }

        eliminate_multi_thread(matrix, rows, cols, row, num_threads);
    }

    // remove minus zeros from result column
    int64_t solution_col = cols - 1;
    for (int64_t i = 0; i < rows; i++)
    {
        float* val_ptr = at(matrix, cols, i, solution_col);
        if (is_zero(*val_ptr))
        {
            *val_ptr = 0.f;
        }
    }

    return solutions_in_system(matrix, rows, cols);
}