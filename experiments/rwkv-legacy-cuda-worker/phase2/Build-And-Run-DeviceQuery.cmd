@echo off
setlocal
set "ROOT=%~dp0"
set "CUDA_BIN=%CUDA_PATH%\bin"
if not exist "%CUDA_BIN%\nvcc.exe" set "CUDA_BIN=%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\v6.5\bin"
set "NVCC=%CUDA_BIN%\nvcc.exe"
set "SOURCE=%ROOT%device-probe.cu"
set "EXE=%ROOT%deviceQuery.exe"
set "REPORT=%ROOT%device-query-report.txt"
set "VCVARS="

if exist "%VS140COMNTOOLS%..\..\VC\vcvarsall.bat" set "VCVARS=%VS140COMNTOOLS%..\..\VC\vcvarsall.bat"
if not defined VCVARS if exist "%VS120COMNTOOLS%..\..\VC\vcvarsall.bat" set "VCVARS=%VS120COMNTOOLS%..\..\VC\vcvarsall.bat"
if not defined VCVARS if exist "%VS110COMNTOOLS%..\..\VC\vcvarsall.bat" set "VCVARS=%VS110COMNTOOLS%..\..\VC\vcvarsall.bat"
if not defined VCVARS if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat" set "VCVARS=%ProgramFiles(x86)%\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat"
if not defined VCVARS if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" set "VCVARS=%ProgramFiles(x86)%\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
if not defined VCVARS if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" set "VCVARS=%ProgramFiles(x86)%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat"
if not defined VCVARS if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" set "VCVARS=%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"

if defined VCVARS (
    echo Loading Visual Studio compiler environment...
    call "%VCVARS%" x64 >nul
)

set "SELF=%~f0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$self=$env:SELF; $out=$env:SOURCE; $begin='### BEGIN CUDA '+'SOURCE ###'; $finish='### END CUDA '+'SOURCE ###'; $lines=[System.IO.File]::ReadAllLines($self); $start=[Array]::IndexOf($lines,$begin); $end=[Array]::IndexOf($lines,$finish); if($start -lt 0 -or $end -le $start){throw 'Embedded CUDA source markers were not found.'}; $source=$lines[($start+1)..($end-1)] -join [Environment]::NewLine; [System.IO.File]::WriteAllText($out,$source,(New-Object System.Text.UTF8Encoding($false)))"
if errorlevel 1 (
    echo Could not extract the embedded CUDA source.
    pause
    exit /b 3
)

if not exist "%NVCC%" (
    echo CUDA 6.5 nvcc.exe was not found.
    echo Expected: "%NVCC%"
    pause
    exit /b 2
)

where cl.exe >nul 2>&1
if errorlevel 1 (
    echo Microsoft cl.exe was not found.
    echo CUDA 6.5 on Windows requires a compatible Visual C++ compiler.
    echo Install or repair Visual Studio 2013 C++ tools, then run this file again.
    pause
    exit /b 5
)

echo Building deviceQuery.exe for sm_11 with CUDA 6.5...
"%NVCC%" -m64 -arch=sm_11 -o "%EXE%" "%SOURCE%"
if errorlevel 1 (
    echo.
    echo CUDA device probe compilation failed.
    echo This usually means the CUDA 6.5 host compiler is unavailable or incompatible.
    pause
    exit /b 4
)

echo.
echo Running deviceQuery.exe...
"%EXE%" > "%REPORT%" 2>&1
set "RC=%ERRORLEVEL%"
type "%REPORT%"
echo.
if not "%RC%"=="0" (
    echo Device query returned exit code %RC%.
) else (
    echo Device query completed successfully.
)
echo Report: "%REPORT%"
pause
exit /b %RC%

### BEGIN CUDA SOURCE ###
#include <cuda_runtime.h>
#include <stdio.h>

static void print_cuda_error(const char* operation, cudaError_t error) {
    fprintf(stderr, "%s failed: %s (%d)\n", operation, cudaGetErrorString(error), (int)error);
}

int main(void) {
    int device_count = 0;
    cudaError_t error = cudaGetDeviceCount(&device_count);
    if (error != cudaSuccess) {
        print_cuda_error("cudaGetDeviceCount", error);
        return 2;
    }

    printf("CUDA device count: %d\n", device_count);
    if (device_count <= 0) {
        printf("No CUDA device reported.\n");
        return 3;
    }

    for (int index = 0; index < device_count; ++index) {
        cudaDeviceProp properties;
        error = cudaGetDeviceProperties(&properties, index);
        if (error != cudaSuccess) {
            print_cuda_error("cudaGetDeviceProperties", error);
            return 4;
        }

        size_t free_bytes = 0;
        size_t total_bytes = 0;
        error = cudaSetDevice(index);
        if (error != cudaSuccess) {
            print_cuda_error("cudaSetDevice", error);
            return 5;
        }
        error = cudaMemGetInfo(&free_bytes, &total_bytes);
        if (error != cudaSuccess) {
            print_cuda_error("cudaMemGetInfo", error);
            return 6;
        }

        printf("Device %d name: %s\n", index, properties.name);
        printf("Device %d compute capability: %d.%d\n", index, properties.major, properties.minor);
        printf("Device %d totalGlobalMemBytes: %llu\n", index, (unsigned long long)properties.totalGlobalMem);
        printf("Device %d freeMemBytes: %llu\n", index, (unsigned long long)free_bytes);
        printf("Device %d memInfoTotalBytes: %llu\n", index, (unsigned long long)total_bytes);
        printf("Device %d multiProcessorCount: %d\n", index, properties.multiProcessorCount);
        printf("Device %d clockRateKHz: %d\n", index, properties.clockRate);
        printf("Device %d integrated: %d\n", index, properties.integrated);
    }

    printf("Probe completed. No deliberate device allocation was performed.\n");
    return 0;
}
### END CUDA SOURCE ###
