#!/bin/bash
set -u

clear
printf "\n========================================\n"
printf "  Codex macOS 一键安装\n"
printf "========================================\n\n"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/install-codex-macos.sh"

pause_and_exit() {
  local code="${1:-0}"
  printf "\n按回车键退出..."
  read -r _
  exit "$code"
}

if [ "$(uname -s)" != "Darwin" ]; then
  printf "当前不是 macOS。\n"
  printf "Windows 用户请双击“双击安装Codex.cmd”。\n"
  pause_and_exit 1
fi

if [ ! -f "$INSTALL_SCRIPT" ]; then
  printf "未找到安装脚本：\n%s\n\n" "$INSTALL_SCRIPT"
  printf "请确认本文件和 install-codex-macos.sh 在同一个解压目录中。\n"
  pause_and_exit 1
fi

chmod +x "$INSTALL_SCRIPT" 2>/dev/null || true
xattr -dr com.apple.quarantine "$SCRIPT_DIR" 2>/dev/null || true

"$INSTALL_SCRIPT"
status=$?

if [ "$status" -eq 0 ]; then
  printf "\nCodex 安装流程已结束。重新打开终端后可运行：\n"
  printf "  codex --version\n"
  printf "  codex\n"
else
  printf "\nCodex 安装失败，退出码：%s\n" "$status"
fi

pause_and_exit "$status"
