@echo off
setlocal
set "REPORT=%~dp0phase0-toolchain-check.txt"
>"%REPORT%" echo RWKV Legacy CUDA Worker - Phase 0 Toolchain Check
>>"%REPORT%" echo Generated: %DATE% %TIME%
>>"%REPORT%" echo.
>>"%REPORT%" echo This check is read-only. It does not compile, allocate, or execute CUDA kernels.
>>"%REPORT%" echo.
>>"%REPORT%" echo [nvcc location]
where nvcc.exe >>"%REPORT%" 2>&1
>>"%REPORT%" echo.
>>"%REPORT%" echo [nvcc version]
nvcc.exe --version >>"%REPORT%" 2>&1
>>"%REPORT%" echo.
>>"%REPORT%" echo [CUDA environment]
echo CUDA_PATH=%CUDA_PATH% >>"%REPORT%"
echo CUDA_PATH_V6_5=%CUDA_PATH_V6_5% >>"%REPORT%"
>>"%REPORT%" echo.
>>"%REPORT%" echo [Expected toolkit files]
if exist "%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\v6.5\bin\nvcc.exe" (>>"%REPORT%" echo nvcc.exe: present) else (>>"%REPORT%" echo nvcc.exe: missing)
if exist "%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\v6.5\bin\cudart64_65.dll" (>>"%REPORT%" echo cudart64_65.dll: present) else (>>"%REPORT%" echo cudart64_65.dll: missing)
if exist "%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\v6.5\lib\x64\cudart.lib" (>>"%REPORT%" echo cudart.lib: present) else (>>"%REPORT%" echo cudart.lib: missing)
>>"%REPORT%" echo.
>>"%REPORT%" echo [Common CUDA sample/device-query locations]
for %%P in ("%ProgramData%\NVIDIA Corporation\CUDA Samples" "%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\v6.5\samples" "%USERPROFILE%\Documents\CUDA Samples") do if exist "%%~P" (>>"%REPORT%" echo present: %%~P) else (>>"%REPORT%" echo absent: %%~P)
>>"%REPORT%" echo.
>>"%REPORT%" echo Phase 0 toolchain check complete. No compilation, allocation, kernel execution, driver, or network action was taken.

echo.
echo Phase 0 toolchain check complete.
echo Report: "%REPORT%"
echo.
pause
exit /b 0
