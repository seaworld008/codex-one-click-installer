#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="$SCRIPT_DIR/install-codex-unix.sh"

if [ ! -f "$CORE_SCRIPT" ]; then
  printf '错误：未找到 Unix 安装核心：%s\n' "$CORE_SCRIPT" >&2
  exit 1
fi

exec /bin/bash "$CORE_SCRIPT" --install-app "$@"
