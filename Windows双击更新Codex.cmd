@echo off
chcp 65001 >nul
setlocal
title Codex 一键更新

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_FILE=%SCRIPT_DIR%install-codex.ps1"
set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" (
  set "POWERSHELL_EXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
)

echo.
echo ========================================
echo   Codex Windows 一键更新
echo ========================================
echo.

if not exist "%SCRIPT_FILE%" (
  echo 未找到安装脚本：
  echo %SCRIPT_FILE%
  echo.
  echo 请确认本文件和 install-codex.ps1 在同一个解压目录中。
  goto :end
)

if not exist "%POWERSHELL_EXE%" (
  echo 未找到 powershell.exe，无法继续自动更新。
  echo 请确认当前系统为 Windows 8/8.1/10/11。
  goto :end
)

"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_FILE%" -Update

:end
echo.
pause
