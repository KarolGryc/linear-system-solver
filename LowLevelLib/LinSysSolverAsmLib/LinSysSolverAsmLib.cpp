#include <iostream>
#include <Windows.h>
#include "Lib.h"

typedef int(__fastcall *MyProc1)(double*, int, int, int);

HINSTANCE dllHandle = NULL;


int main()
{
     //load library
    dllHandle = LoadLibrary(L"LinSysSolverAsm.dll");
    
    if (!dllHandle) {
        std::cout << "Library not loaded!" << std::endl;
        return 1;
    }

    MyProc1 solveAsm = (MyProc1)GetProcAddress(dllHandle, "solve_linear_system");

    
    double matrix[] = {
        1.0, 1.0, 1.0, 3.0,
        0.0, 1.0, 1.0, 2.0,
        1.0, 1.0, 0.0, 3.0
        
        //1.1, 2.2, 3.3, 4.4,
        //6.6, 7.7, 8.8, 9.9,
    };
    
    int rows = 3;
    int cols = 4;
    int num_threads = 1;

    solveAsm(matrix, rows, cols, num_threads);

    solve_linear_system (matrix, rows, cols, num_threads);

    // Helo ³ord
    std::cout << "Hello World!" << std::endl;
    return 0;
}