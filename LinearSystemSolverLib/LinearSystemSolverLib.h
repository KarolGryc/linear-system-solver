#pragma once

#ifdef LINEAR_SYSTEM_SOLVER_LIB_EXPORTS
#define LINEAR_SYSTEM_SOLVER_API __declspec(dllexport)
#else
#define LINEAR_SYSTEM_SOLVER_API __declspec(dllimport)
#endif

extern "C" LINEAR_SYSTEM_SOLVER_API void solve_matrix_equation_system(double* matrix, unsigned rowCount, unsigned colCount);