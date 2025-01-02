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
        1.1, 2.2, 3.3,
        4.4, 5.5, 6.6
    };
    
    int rows = 2;
    int cols = 3;
    int num_threads = 1;

    solveAsm(matrix, rows, cols, num_threads);

    // Helo ³ord
    std::cout << "Hello World!" << std::endl;
    return 0;
}