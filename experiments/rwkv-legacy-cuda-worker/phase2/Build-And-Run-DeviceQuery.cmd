@echo off
setlocal
set "ROOT=%~dp0"
set "CUDA_BIN=%CUDA_PATH%\bin"
if not exist "%CUDA_BIN%\nvcc.exe" set "CUDA_BIN=%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\v6.5\bin"
set "NVCC=%CUDA_BIN%\nvcc.exe"
set "SOURCE=%ROOT%device-probe.cu"
set "EXE=%ROOT%deviceQuery.exe"
set "REPORT=%ROOT%device-query-report.txt"

if not exist "%NVCC%" (
    echo CUDA 6.5 nvcc.exe was not found.
    echo Expected: "%NVCC%"
    pause
    exit /b 2
)

if not exist "%SOURCE%" (
    echo Missing source: "%SOURCE%"
    pause
    exit /b 3
)

echo Building deviceQuery.exe for sm_11 with CUDA 6.5...
"%NVCC%" -arch=sm_11 -o "%EXE%" "%SOURCE%"
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
