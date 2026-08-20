@echo off
setlocal EnableExtensions

rem Double-click launcher for a read-only Windows host survey.
rem No model, driver, toolkit, or other software is installed or executed.

set "TOOL_DIR=%~dp0"
set "REPORT_DIR=%TOOL_DIR%reports"

if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%"

for /f %%I in ('powershell.exe -NoLogo -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "STAMP=%%I"
set "REPORT=%REPORT_DIR%\host-report-%STAMP%.json"
set "LOG=%REPORT_DIR%\host-report-%STAMP%.log"
set "LATEST_REPORT=%REPORT_DIR%\latest-host-report.json"

echo.
echo Model Surveyor
echo Read-only inventory in progress. This can take a few seconds...
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%TOOL_DIR%model-surveyor.ps1" inventory -OutputJson "%REPORT%" > "%LOG%" 2>&1
if errorlevel 1 goto :failed
copy /y "%REPORT%" "%LATEST_REPORT%" >nul

echo Survey complete.
echo.
echo Report: %REPORT%
echo Latest: %LATEST_REPORT%
echo Log:    %LOG%
echo.
echo Bring back the JSON report. Do not edit it.
start "" explorer.exe /select,"%REPORT%"
exit /b 0

:failed
echo Survey failed. The log will open now.
echo.
type "%LOG%"
start "" notepad.exe "%LOG%"
pause
exit /b 1

