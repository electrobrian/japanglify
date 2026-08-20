@echo off
setlocal EnableExtensions

rem Double-click launcher for the read-only CI Pipeline Dashboard.
rem It opens PowerShell without requiring an execution-policy change.

set "SCRIPT_DIR=%~dp0"
set "DASHBOARD=%SCRIPT_DIR%ci-pipeline-dashboard.ps1"

if not exist "%DASHBOARD%" (
  echo Dashboard script not found:
  echo %DASHBOARD%
  pause
  exit /b 1
)

start "Japanglify CI Pipeline Dashboard" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -File "%DASHBOARD%"
exit /b 0
