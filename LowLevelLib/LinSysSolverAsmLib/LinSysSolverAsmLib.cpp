#include <iostream>
#include <Windows.h>
#include <vector>
#include <chrono>
#include "Lib.h"

typedef int(__fastcall *MatrixSolveFunc)(float*, int, int, int);

HINSTANCE dllHandle = NULL;

int main()
{
     //load library
    dllHandle = LoadLibrary(L"LinSysSolverAsm.dll");
    
    if (!dllHandle) {
        std::cout << "Library not loaded!" << std::endl;
        return 1;
    }

    MatrixSolveFunc solveAsm = (MatrixSolveFunc)GetProcAddress(dllHandle, "solve_linear_system");

    float matrix[] = {
        1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0,
        0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0,
        0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3.0,
        0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 4.0,
        0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 5.0,
        0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 6.0,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 7.0,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 8.0,
    };
    
    int rows = 8;
    int cols = 9;
    int num_threads = 1;

    solveAsm(matrix, rows, cols, num_threads);

    std::cout << "Hello World!" << std::endl;
    return 0;
}