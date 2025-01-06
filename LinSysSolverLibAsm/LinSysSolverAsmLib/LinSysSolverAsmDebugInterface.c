#include <Windows.h>
#include <stdio.h>

typedef int(__fastcall *MatrixSolveFunc)(float*, int, int, int);

HINSTANCE dllHandle = NULL;

int main()
{
     //load library
    dllHandle = LoadLibrary(L"LinSysSolverAsm.dll");
    
    if (!dllHandle) {
        printf("Library not loaded!");
        return 1;
    }

    MatrixSolveFunc solveAsm = (MatrixSolveFunc)GetProcAddress(dllHandle, "solve_linear_system");
    //float matrix[] = {
    //    1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0,
    //    0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0,
    //    0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3.0,
    //    0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 4.0,
    //    0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 5.0,
    //    0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 6.0,
    //    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 7.0,
    //    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 8.0,
    //};

    //float matrix[] = {
    //    1.0, 1.0, 2.0,
    //    1.0, 1.0, 2.0, 
    //};

    float matrix[] = {
        0.f,1.f, 0.f, 0.f, 3.f, 0.f,1.f, 0.f, 0.f, 3.f, 1.f, 1.f, 1.f, 1.f, 1.f, 1.f,
        0.f, 0.f, 1.f, 0.f, 5.f,0.f,1.f, 0.f, 0.f, 3.f, 1.f, 1.f, 1.f, 1.f, 1.f, 1.f,
        0.f, 0.f, 0.f, 1.f, 7.f,0.f,1.f, 0.f, 0.f, 3.f, 1.f, 1.f, 1.f, 1.f, 1.f, 1.f,
        -1.f, 1.f, 1.f, 1.f, 0.f,0.f,1.f,0.f, 0.f, 3.f, 1.f, 1.f, 1.f, 1.f, 1.f, 1.f,
    };

    int rows = 4;
    int cols = 16;
    int num_threads = 1;

    int x = solveAsm(matrix, rows, cols, num_threads);
    printf("%d", x);

    return 0;
}