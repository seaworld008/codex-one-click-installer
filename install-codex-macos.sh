#!/usr/bin/env bash
set -euo pipefail

# Codex macOS 一键安装脚本
# 支持：macOS 13.5+，x64 / arm64

NODE_VERSION="${CODEX_NODE_VERSION:-24.18.0}"
PYTHON_VERSION="${CODEX_PYTHON_VERSION:-3.14.6}"
INSTALL_ROOT="${CODEX_INSTALL_ROOT:-$HOME/.local/codex-installer}"
NODE_ROOT="$INSTALL_ROOT/node"
NPM_PREFIX="${CODEX_NPM_PREFIX:-$INSTALL_ROOT/npm-global}"
WORK_DIR="${TMPDIR:-/tmp}/codex-installer"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$WORK_DIR/install-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$WORK_DIR" "$NODE_ROOT" "$NPM_PREFIX"
exec > >(tee -a "$LOG_FILE") 2>&1

step() {
  printf "\n========== %s ==========\n" "$1"
}

info() {
  printf "%s\n" "$1"
}

fail() {
  printf "\n安装失败：%s\n日志位置：%s\n" "$1" "$LOG_FILE" >&2
  exit 1
}

version_ge() {
  local current="$1"
  local required="$2"
  [ "$(printf '%s\n%s\n' "$required" "$current" | sort -V | head -n 1)" = "$required" ]
}

download_file() {
  local name="$1"
  local url="$2"
  local out="$3"

  step "下载 $name"
  if [ -f "$out" ] && [ "$(wc -c < "$out")" -gt 1048576 ]; then
    info "已存在，跳过下载：$out"
    return
  fi

  curl -fL --retry 3 --connect-timeout 20 "$url" -o "$out"
  [ -f "$out" ] || fail "下载失败：$name"
  [ "$(wc -c < "$out")" -gt 1048576 ] || fail "下载文件异常：$name"
}

append_path_once() {
  local profile="$1"
  local marker="# codex-one-click-installer"
  local line="export PATH=\"$NODE_ROOT/current/bin:$NPM_PREFIX/bin:\$PATH\""

  touch "$profile"
  if ! grep -Fq "$marker" "$profile"; then
    {
      printf "\n%s\n" "$marker"
      printf "%s\n" "$line"
    } >> "$profile"
    info "已写入 PATH：$profile"
  fi
}

toml_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

ensure_system() {
  step "系统检查"
  [ "$(uname -s)" = "Darwin" ] || fail "当前系统不是 macOS。"

  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64) CODEX_ARCH="x64" ;;
    arm64) CODEX_ARCH="arm64" ;;
    *) fail "当前架构不支持：$arch。Codex 官方 npm 包只发布 darwin-x64 / darwin-arm64。" ;;
  esac

  MACOS_VERSION="$(sw_vers -productVersion)"
  info "系统：macOS $MACOS_VERSION"
  info "架构：$CODEX_ARCH"

  if ! version_ge "$MACOS_VERSION" "13.5"; then
    fail "当前官方 Node.js 24 LTS 二进制要求 macOS 13.5+。当前 macOS $MACOS_VERSION 不自动安装，请升级系统或手动准备受支持的 Node.js 16+ 后再安装 Codex。"
  fi
}

ensure_git() {
  step "检查 Git"
  if command -v git >/dev/null 2>&1; then
    git --version
    return
  fi

  info "未检测到 Git。macOS 上推荐通过 Apple Command Line Tools 安装。"
  xcode-select --install >/dev/null 2>&1 || true
  fail "已尝试打开 Command Line Tools 安装窗口。请安装完成后重新运行本脚本。"
}

ensure_node() {
  step "检查 Node.js"
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
    if [ "$major" -ge 16 ]; then
      node -v
      npm -v
      return
    fi
  fi

  local dist="node-v$NODE_VERSION-darwin-$CODEX_ARCH"
  local url="${CODEX_NODE_URL:-https://nodejs.org/dist/v$NODE_VERSION/$dist.tar.gz}"
  local tarball="$WORK_DIR/$dist.tar.gz"
  local target="$NODE_ROOT/$dist"

  download_file "Node.js" "$url" "$tarball"
  rm -rf "$target"
  tar -xzf "$tarball" -C "$NODE_ROOT"
  ln -sfn "$target" "$NODE_ROOT/current"
  export PATH="$NODE_ROOT/current/bin:$NPM_PREFIX/bin:$PATH"

  node -v
  npm -v
}

ensure_python() {
  step "检查 Python"
  if command -v python3 >/dev/null 2>&1; then
    python3 --version
    return
  fi

  local url="${CODEX_PYTHON_URL:-https://www.python.org/ftp/python/$PYTHON_VERSION/python-$PYTHON_VERSION-macos11.pkg}"
  local pkg="$WORK_DIR/python-$PYTHON_VERSION-macos11.pkg"

  download_file "Python" "$url" "$pkg"
  sudo installer -pkg "$pkg" -target /
  python3 --version
}

install_codex_cli() {
  step "安装 Codex CLI"
  mkdir -p "$NPM_PREFIX"
  npm config set prefix "$NPM_PREFIX"
  if [ -n "${CODEX_NPM_REGISTRY:-}" ]; then
    npm config set registry "$CODEX_NPM_REGISTRY"
  fi

  export PATH="$NODE_ROOT/current/bin:$NPM_PREFIX/bin:$PATH"
  npm install -g @openai/codex@latest
}

install_skills() {
  step "安装 Codex Skills"
  local zip_file=""

  if [ -f "$SCRIPT_DIR/codex-skills.zip" ]; then
    zip_file="$SCRIPT_DIR/codex-skills.zip"
  elif [ -n "${CODEX_SKILLS_URL:-}" ]; then
    zip_file="$WORK_DIR/codex-skills.zip"
    download_file "Codex Skills" "$CODEX_SKILLS_URL" "$zip_file"
  else
    info "未配置 Skills 包，跳过 Skills 安装。可使用 CODEX_SKILLS_URL 或同目录 codex-skills.zip 启用。"
    return
  fi

  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$HOME/.agents/skills"
  ditto -x -k "$zip_file" "$tmp"

  while IFS= read -r skill_file; do
    local dir
    local name
    dir="$(dirname "$skill_file")"
    name="$(basename "$dir")"
    rm -rf "$HOME/.agents/skills/$name"
    cp -R "$dir" "$HOME/.agents/skills/$name"
    info "已安装 Skill：$name"
  done < <(find "$tmp" -name SKILL.md -type f)

  rm -rf "$tmp"
}

write_codex_config() {
  step "写入 Codex 配置"
  local codex_home="$HOME/.codex"
  local config="$codex_home/config.toml"
  local auth="$codex_home/auth.json"
  mkdir -p "$codex_home"

  if [ -f "$config" ]; then
    local backup="$codex_home/config.toml.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$config" "$backup"
    info "已备份旧配置：$backup"
  fi

  {
    printf 'disable_response_storage = true\n'
    printf 'network_access = "enabled"\n'
    if [ -n "${CODEX_MODEL:-}" ]; then
      printf 'model = "%s"\n' "$(toml_escape "$CODEX_MODEL")"
    fi
    if [ -n "${CODEX_BASE_URL:-}" ]; then
      printf '\n[model_providers.OpenAI]\n'
      printf 'name = "OpenAI"\n'
      printf 'base_url = "%s"\n' "$(toml_escape "$CODEX_BASE_URL")"
      printf 'wire_api = "responses"\n'
      printf 'requires_openai_auth = true\n'
    fi
  } > "$config"
  info "已写入：$config"

  if [ -f "$SCRIPT_DIR/codex-auth.json" ]; then
    cp "$SCRIPT_DIR/codex-auth.json" "$auth"
    chmod 600 "$auth"
    info "已从脚本同目录 codex-auth.json 写入认证文件：$auth"
    return
  fi

  printf "\n请输入 OPENAI_API_KEY。直接回车则跳过，不覆盖已有 auth.json。\n"
  read -r -s -p "OPENAI_API_KEY: " api_key
  printf "\n"
  if [ -n "$api_key" ]; then
    printf '{"OPENAI_API_KEY":"%s"}\n' "$api_key" > "$auth"
    chmod 600 "$auth"
    info "已写入：$auth"
  elif [ -f "$auth" ]; then
    info "保留已有认证文件：$auth"
  else
    info "未写入 auth.json。后续首次运行 codex 时需要手动登录或配置密钥。"
  fi
}

show_versions() {
  step "版本检查"
  git --version || true
  node -v || true
  npm -v || true
  python3 --version || true
  codex --version || true
}

main() {
  info "Codex macOS 一键安装开始。日志文件：$LOG_FILE"
  ensure_system
  ensure_git
  ensure_node
  ensure_python
  install_codex_cli
  install_skills
  write_codex_config
  append_path_once "$HOME/.zshrc"
  show_versions

  printf "\n安装完成。请重新打开终端，然后执行：\n"
  printf "  codex --version\n"
  printf "  codex\n"
  printf "\n日志位置：%s\n" "$LOG_FILE"
}

main "$@"
