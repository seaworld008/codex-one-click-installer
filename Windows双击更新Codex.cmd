@echo off
setlocal
title Codex Updater

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_FILE=%SCRIPT_DIR%install-codex.ps1"
set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" (
  set "POWERSHELL_EXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
)

echo.
echo ========================================
echo   Codex Windows Updater
echo ========================================
echo.

if not exist "%SCRIPT_FILE%" (
  echo install-codex.ps1 was not found:
  echo %SCRIPT_FILE%
  echo.
  echo Make sure this file and install-codex.ps1 are in the same extracted folder.
  goto :end
)

if not exist "%POWERSHELL_EXE%" (
  echo powershell.exe was not found. Cannot continue.
  echo Please run this on Windows 8/8.1/10/11.
  goto :end
)

"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_FILE%" -Update

:end
echo.
pause
