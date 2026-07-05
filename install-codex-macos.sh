#!/usr/bin/env bash
set -euo pipefail

# Codex macOS 一键安装脚本
# 支持：macOS 13.5+，x64 / arm64

NODE_VERSION="${CODEX_NODE_VERSION:-22.17.0}"
PYTHON_VERSION="${CODEX_PYTHON_VERSION:-3.12.10}"
INSTALL_ROOT="${CODEX_INSTALL_ROOT:-$HOME/.local/codex-installer}"
NODE_ROOT="$INSTALL_ROOT/node"
NPM_PREFIX="${CODEX_NPM_PREFIX:-$INSTALL_ROOT/npm-global}"
WORK_DIR="${TMPDIR:-/tmp}/codex-installer"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$WORK_DIR/install-$(date +%Y%m%d-%H%M%S).log"
DOWNLOAD_MIRROR="${CODEX_DOWNLOAD_MIRROR:-china}"
CHECK_ONLY="${CODEX_CHECK_ONLY:-0}"
VERIFY_DOWNLOADS="${CODEX_VERIFY_DOWNLOADS:-0}"
NON_INTERACTIVE="${CODEX_NONINTERACTIVE:-0}"
SKIP_PYTHON="${CODEX_SKIP_PYTHON:-0}"
SKIP_SKILLS="${CODEX_SKIP_SKILLS:-0}"

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

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --check-only) CHECK_ONLY=1 ;;
      --verify-downloads) VERIFY_DOWNLOADS=1 ;;
      --non-interactive) NON_INTERACTIVE=1 ;;
      --skip-python) SKIP_PYTHON=1 ;;
      --skip-skills) SKIP_SKILLS=1 ;;
      --mirror)
        shift
        [ "$#" -gt 0 ] || fail "--mirror 需要参数：china 或 official"
        DOWNLOAD_MIRROR="$1"
        ;;
      --help|-h)
        printf "用法：%s [--check-only] [--verify-downloads] [--non-interactive] [--skip-python] [--skip-skills] [--mirror china|official]\n" "$0"
        exit 0
        ;;
      *) fail "未知参数：$1" ;;
    esac
    shift
  done
}

version_ge() {
  local current="$1"
  local required="$2"
  local c1 c2 c3 r1 r2 r3
  IFS=. read -r c1 c2 c3 <<EOF
$current
EOF
  IFS=. read -r r1 r2 r3 <<EOF
$required
EOF
  c1="${c1:-0}"; c2="${c2:-0}"; c3="${c3:-0}"
  r1="${r1:-0}"; r2="${r2:-0}"; r3="${r3:-0}"
  [ "$c1" -gt "$r1" ] && return 0
  [ "$c1" -lt "$r1" ] && return 1
  [ "$c2" -gt "$r2" ] && return 0
  [ "$c2" -lt "$r2" ] && return 1
  [ "$c3" -ge "$r3" ]
}

download_file() {
  local name="$1"
  local out="$2"
  shift 2
  local urls=("$@")

  step "下载 $name"
  if [ -f "$out" ] && [ "$(wc -c < "$out")" -gt 1048576 ]; then
    info "已存在，跳过下载：$out"
    return
  fi

  local url
  for url in "${urls[@]}"; do
    [ -n "$url" ] || continue
    info "来源：$url"
    rm -f "$out"
    if curl -fL --retry 3 --connect-timeout 20 --max-time 300 "$url" -o "$out"; then
      [ -f "$out" ] || fail "下载失败：$name"
      if [ "$(wc -c < "$out")" -gt 1048576 ]; then
        return
      fi
      info "下载文件过小，可能是错误页或被代理拦截。"
    fi
  done

  fail "下载失败或文件异常：$name"
}

check_url() {
  local name="$1"
  local url="$2"
  if curl -fsIL --connect-timeout 15 --max-time 45 "$url" >/dev/null; then
    info "$name 可访问：$url"
    return 0
  fi
  info "$name 当前不可访问：$url"
  return 1
}

url_candidates() {
  local override="$1"
  local china="$2"
  local official="$3"

  if [ -n "$override" ]; then
    printf '%s\n' "$override"
    return
  fi

  case "$DOWNLOAD_MIRROR" in
    official)
      printf '%s\n%s\n' "$official" "$china"
      ;;
    china|"")
      printf '%s\n%s\n' "$china" "$official"
      ;;
    *)
      info "未知下载源模式：$DOWNLOAD_MIRROR，已改用 china。"
      DOWNLOAD_MIRROR="china"
      printf '%s\n%s\n' "$china" "$official"
      ;;
  esac
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
  arch="${CODEX_TEST_ARCH:-$(uname -m)}"
  case "$arch" in
    x86_64|x64) CODEX_ARCH="x64" ;;
    arm64) CODEX_ARCH="arm64" ;;
    *) fail "当前架构不支持：$arch。Codex 官方 npm 包只发布 darwin-x64 / darwin-arm64。" ;;
  esac

  MACOS_VERSION="${CODEX_TEST_MACOS_VERSION:-$(sw_vers -productVersion)}"
  info "系统：macOS $MACOS_VERSION"
  info "架构：$CODEX_ARCH"
  info "下载源模式：$DOWNLOAD_MIRROR"
  info "日志位置：$LOG_FILE"

  if ! version_ge "$MACOS_VERSION" "13.5"; then
    fail "当前脚本默认依赖要求 macOS 13.5+。当前 macOS $MACOS_VERSION 不自动安装，请升级系统或手动准备受支持的 Node.js 16+ 后再安装 Codex。"
  fi
}

show_download_plan() {
  step "安装计划"
  local node_dist="node-v$NODE_VERSION-darwin-$CODEX_ARCH"
  local node_urls=()
  local python_urls=()
  local url
  while IFS= read -r url; do node_urls+=("$url"); done < <(url_candidates "${CODEX_NODE_URL:-}" "https://npmmirror.com/mirrors/node/v$NODE_VERSION/$node_dist.tar.gz" "https://nodejs.org/dist/v$NODE_VERSION/$node_dist.tar.gz")
  while IFS= read -r url; do python_urls+=("$url"); done < <(url_candidates "${CODEX_PYTHON_URL:-}" "https://npmmirror.com/mirrors/python/$PYTHON_VERSION/python-$PYTHON_VERSION-macos11.pkg" "https://www.python.org/ftp/python/$PYTHON_VERSION/python-$PYTHON_VERSION-macos11.pkg")

  info "Node.js：$node_dist.tar.gz"
  for url in "${node_urls[@]}"; do info "  - $url"; done
  if [ "$SKIP_PYTHON" != "1" ]; then
    info "Python：python-$PYTHON_VERSION-macos11.pkg"
    for url in "${python_urls[@]}"; do info "  - $url"; done
  fi
  if [ -n "${CODEX_NPM_REGISTRY:-}" ]; then
    info "npm registry：$CODEX_NPM_REGISTRY"
  elif [ "$DOWNLOAD_MIRROR" = "china" ]; then
    info "npm registry：https://registry.npmmirror.com"
  fi
}

verify_download_plan() {
  step "下载源可达性检查"
  local node_dist="node-v$NODE_VERSION-darwin-$CODEX_ARCH"
  local node_urls=()
  local python_urls=()
  local url ok
  while IFS= read -r url; do node_urls+=("$url"); done < <(url_candidates "${CODEX_NODE_URL:-}" "https://npmmirror.com/mirrors/node/v$NODE_VERSION/$node_dist.tar.gz" "https://nodejs.org/dist/v$NODE_VERSION/$node_dist.tar.gz")
  ok=0
  for url in "${node_urls[@]}"; do
    if check_url "Node.js" "$url"; then ok=1; break; fi
  done
  [ "$ok" = "1" ] || fail "Node.js 所有下载源都不可访问。请检查网络/代理，或配置 CODEX_NODE_URL。"

  if [ "$SKIP_PYTHON" != "1" ]; then
    while IFS= read -r url; do python_urls+=("$url"); done < <(url_candidates "${CODEX_PYTHON_URL:-}" "https://npmmirror.com/mirrors/python/$PYTHON_VERSION/python-$PYTHON_VERSION-macos11.pkg" "https://www.python.org/ftp/python/$PYTHON_VERSION/python-$PYTHON_VERSION-macos11.pkg")
    ok=0
    for url in "${python_urls[@]}"; do
      if check_url "Python" "$url"; then ok=1; break; fi
    done
    [ "$ok" = "1" ] || fail "Python 所有下载源都不可访问。请检查网络/代理，或配置 CODEX_PYTHON_URL。"
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
  local tarball="$WORK_DIR/$dist.tar.gz"
  local target="$NODE_ROOT/$dist"
  local urls=()
  while IFS= read -r url; do urls+=("$url"); done < <(url_candidates "${CODEX_NODE_URL:-}" "https://npmmirror.com/mirrors/node/v$NODE_VERSION/$dist.tar.gz" "https://nodejs.org/dist/v$NODE_VERSION/$dist.tar.gz")

  download_file "Node.js" "$tarball" "${urls[@]}"
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

  local pkg="$WORK_DIR/python-$PYTHON_VERSION-macos11.pkg"
  local urls=()
  while IFS= read -r url; do urls+=("$url"); done < <(url_candidates "${CODEX_PYTHON_URL:-}" "https://npmmirror.com/mirrors/python/$PYTHON_VERSION/python-$PYTHON_VERSION-macos11.pkg" "https://www.python.org/ftp/python/$PYTHON_VERSION/python-$PYTHON_VERSION-macos11.pkg")

  download_file "Python" "$pkg" "${urls[@]}"
  sudo installer -pkg "$pkg" -target /
  python3 --version
}

install_codex_cli() {
  step "安装 Codex CLI"
  mkdir -p "$NPM_PREFIX"
  npm config set prefix "$NPM_PREFIX"
  local registry="${CODEX_NPM_REGISTRY:-}"
  if [ -z "$registry" ] && [ "$DOWNLOAD_MIRROR" = "china" ]; then
    registry="https://registry.npmmirror.com"
  fi

  export PATH="$NODE_ROOT/current/bin:$NPM_PREFIX/bin:$PATH"
  if [ -n "$registry" ]; then
    npm config set registry "$registry"
  fi
  if npm install -g @openai/codex@latest; then
    return
  fi
  if [ "$registry" = "https://registry.npmmirror.com" ]; then
    info "npmmirror 安装失败，改用官方 npm registry 重试。"
    npm config set registry "https://registry.npmjs.org"
    npm install -g @openai/codex@latest
    return
  fi
  fail "npm install -g @openai/codex@latest 执行失败。请检查 registry、代理或证书。"
}

install_skills() {
  step "安装 Codex Skills"
  local zip_file=""

  if [ -f "$SCRIPT_DIR/codex-skills.zip" ]; then
    zip_file="$SCRIPT_DIR/codex-skills.zip"
  elif [ -n "${CODEX_SKILLS_URL:-}" ]; then
    zip_file="$WORK_DIR/codex-skills.zip"
    download_file "Codex Skills" "$zip_file" "$CODEX_SKILLS_URL"
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

  if [ "$NON_INTERACTIVE" = "1" ]; then
    if [ -f "$auth" ]; then
      info "非交互模式：保留已有认证文件：$auth"
    else
      info "非交互模式：未写入 auth.json。后续首次运行 codex 时需要手动登录或配置密钥。"
    fi
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
  parse_args "$@"
  info "Codex macOS 一键安装开始。日志文件：$LOG_FILE"
  ensure_system
  show_download_plan
  if [ "$VERIFY_DOWNLOADS" = "1" ]; then
    verify_download_plan
  fi
  if [ "$CHECK_ONLY" = "1" ]; then
    printf "\nCheckOnly 预检完成：未执行安装、未写入 Codex 配置。\n"
    return
  fi
  ensure_git
  ensure_node
  if [ "$SKIP_PYTHON" != "1" ]; then
    ensure_python
  fi
  install_codex_cli
  if [ "$SKIP_SKILLS" != "1" ]; then
    install_skills
  fi
  write_codex_config
  append_path_once "$HOME/.zshrc"
  show_versions

  printf "\n安装完成。请重新打开终端，然后执行：\n"
  printf "  codex --version\n"
  printf "  codex\n"
  printf "\n日志位置：%s\n" "$LOG_FILE"
}

main "$@"
