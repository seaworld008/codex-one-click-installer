@echo off
setlocal EnableExtensions
title Codex Installer

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_FILE=%SCRIPT_DIR%install-codex.ps1"
set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "EXIT_CODE=0"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" (
  set "POWERSHELL_EXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
)

echo.
echo ========================================
echo   Codex Windows Installer
echo ========================================
echo.

if not exist "%SCRIPT_FILE%" (
  echo install-codex.ps1 was not found:
  echo "%SCRIPT_FILE%"
  echo.
  echo Make sure this file and install-codex.ps1 are in the same extracted folder.
  set "EXIT_CODE=2"
  goto :finish
)

if not exist "%POWERSHELL_EXE%" (
  echo powershell.exe was not found. Cannot continue.
  echo Windows PowerShell 5.1 on Windows 10/11 is required.
  set "EXIT_CODE=3"
  goto :finish
)

"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_FILE%" -InstallDesktopApp -NoPause
set "EXIT_CODE=%ERRORLEVEL%"

:finish
echo.
echo Installer exit code: %EXIT_CODE%
pause >nul
endlocal & exit /b %EXIT_CODE%
