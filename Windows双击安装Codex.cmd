@echo off
chcp 65001 >nul
setlocal
title Codex 一键安装

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_FILE=%SCRIPT_DIR%install-codex.ps1"

echo.
echo ========================================
echo   Codex Windows 一键安装
echo ========================================
echo.

if not exist "%SCRIPT_FILE%" (
  echo 未找到安装脚本：
  echo %SCRIPT_FILE%
  echo.
  echo 请确认本文件和 install-codex.ps1 在同一个解压目录中。
  goto :end
)

where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo 未找到 powershell.exe，无法继续自动安装。
  echo 请确认当前系统为 Windows 8/8.1/10/11。
  goto :end
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_FILE%"

:end
echo.
pause
