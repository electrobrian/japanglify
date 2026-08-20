@echo off
setlocal
set "REPORT=%~dp0phase0-cuda-readiness.txt"
>"%REPORT%" echo RWKV Legacy CUDA Worker - Phase 0 CUDA Readiness Check
>>"%REPORT%" echo Generated: %DATE% %TIME%
>>"%REPORT%" echo.
>>"%REPORT%" echo Read-only check. It does not compile, allocate, or execute CUDA code.
>>"%REPORT%" echo.
>>"%REPORT%" echo [CUDA toolkit]
where nvcc.exe >>"%REPORT%" 2>&1
nvcc.exe --version >>"%REPORT%" 2>&1
>>"%REPORT%" echo.
>>"%REPORT%" echo [CUDA environment]
echo CUDA_PATH=%CUDA_PATH% >>"%REPORT%"
echo CUDA_PATH_V6_5=%CUDA_PATH_V6_5% >>"%REPORT%"
>>"%REPORT%" echo.
>>"%REPORT%" echo [CUDA 6.5 runtime files]
if exist "%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\v6.5\bin\cudart64_65.dll" (>>"%REPORT%" echo cudart64_65.dll: present) else (>>"%REPORT%" echo cudart64_65.dll: missing)
if exist "%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\v6.5\lib\x64\cudart.lib" (>>"%REPORT%" echo cudart.lib: present) else (>>"%REPORT%" echo cudart.lib: missing)
if exist "%WINDIR%\System32\nvcuda.dll" (>>"%REPORT%" echo nvcuda.dll: present) else (>>"%REPORT%" echo nvcuda.dll: missing)
>>"%REPORT%" echo.
>>"%REPORT%" echo [Existing device query programs]
for %%P in ("%ProgramData%\NVIDIA Corporation\CUDA Samples" "%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\v6.5\samples" "%USERPROFILE%\Documents\CUDA Samples" "%USERPROFILE%\source\repos") do if exist "%%~P" (>>"%REPORT%" echo search-root: %%~P) else (>>"%REPORT%" echo absent-root: %%~P)
where deviceQuery.exe >>"%REPORT%" 2>&1
>>"%REPORT%" echo.
>>"%REPORT%" echo [Driver DLL metadata]
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$p=Join-Path $env:WINDIR 'System32\nvcuda.dll'; if(Test-Path $p){(Get-Item $p).VersionInfo | Select-Object FileVersion,ProductVersion,ProductName | Format-List | Out-String | Write-Output}else{'nvcuda.dll metadata unavailable'}" >>"%REPORT%" 2>&1
>>"%REPORT%" echo.
>>"%REPORT%" echo Phase 0 CUDA readiness check complete. No compilation, allocation, kernel execution, driver, or network action was taken.
echo.
echo Phase 0 CUDA readiness check complete.
echo Report: "%REPORT%"
echo.
pause
exit /b 0
