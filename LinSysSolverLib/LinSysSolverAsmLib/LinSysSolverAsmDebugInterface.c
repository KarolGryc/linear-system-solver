#include <Windows.h>
#include <stdio.h>

typedef int(__fastcall* MatrixSolveFunc)(float*, int, int, int);

HINSTANCE dllHandle = NULL;
HINSTANCE cDllHandle = NULL;

int main()
{
    //load library
    dllHandle = LoadLibrary(L"LinSysSolverAsm.dll");
    cDllHandle = LoadLibrary(L"LinSysSolverC.dll");

    if (!dllHandle) {
        printf("Library ASM not loaded!");
        return 1;
    }

    if (!cDllHandle) {
        printf("Library C not loaded!");
        return 2;
    }

    MatrixSolveFunc solveAsm = (MatrixSolveFunc)GetProcAddress(dllHandle, "solve_linear_system");
    MatrixSolveFunc solveC = (MatrixSolveFunc)GetProcAddress(cDllHandle, "solve_linear_system");

    float matrix[500 * 501] = { 0 };
    
    for (int i = 0; i < 500; i++)
    {
        matrix[i * 501 + i] = 1;
    }

    for (int i = 0; i < 500; i++)
    {
        matrix[i * 501 + 500] = 1;
    }

    int rows = 500;
    int cols = 501;
    int num_threads = 1;

    int x = solveAsm(matrix, rows, cols, num_threads);

    printf("ASM: %d", x);

    return 0;
}