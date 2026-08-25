#!/bin/bash
set -u

clear 2>/dev/null || true
printf '\n========================================\n'
printf '  Codex macOS 一键安装\n'
printf '========================================\n\n'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE_SCRIPT="$SCRIPT_DIR/install-codex-unix.sh"
status=0

if [ "$(uname -s)" != "Darwin" ]; then
  printf '当前不是 macOS。\n' >&2
  status=1
elif [ ! -f "$CORE_SCRIPT" ]; then
  printf '未找到安装核心：\n%s\n' "$CORE_SCRIPT" >&2
  printf '请确认本文件和 install-codex-unix.sh 在同一个目录中。\n' >&2
  status=1
else
  /bin/bash "$CORE_SCRIPT" --install-app "$@"
  status=$?
fi

if [ "$status" -eq 0 ]; then
  printf '\nCodex CLI 安装流程已成功完成。\n'
else
  printf '\nCodex 安装流程失败，退出码：%s\n' "$status" >&2
fi

printf '\n按回车键退出...'
IFS= read -r _ || true
exit "$status"
