#!/usr/bin/env bash
set -euo pipefail

# Codex CLI installer for macOS and Linux.
# The default standalone path delegates release selection, binary checksum
# verification, locking, and atomic activation to OpenAI's official bootstrap.

umask 077

# OpenAI documents https://chatgpt.com/codex/install.sh; that entry redirects
# here. Pinning the final official HTTPS endpoint avoids an unnecessary 302.
OFFICIAL_BOOTSTRAP_ENTRY_URL="https://chatgpt.com/codex/install.sh"
OFFICIAL_BOOTSTRAP_URL="https://releases.openai.com/codex/install.sh"
BOOTSTRAP_URL="${CODEX_BOOTSTRAP_URL:-$OFFICIAL_BOOTSTRAP_URL}"
GITHUB_BOOTSTRAP_LATEST_URL="https://github.com/openai/codex/releases/latest/download/install.sh"
BOOTSTRAP_MIN_BYTES=1024
BOOTSTRAP_MAX_BYTES=1048576
LINUX_APP_MAX_BYTES=838860800
LINUX_APP_MIN_BYTES=10485760

UPDATE=0
METHOD="standalone"
NETWORK_MODE="${CODEX_NETWORK_MODE:-auto}"
RELEASE="${CODEX_RELEASE:-latest}"
CHECK_ONLY=0
VERIFY_DOWNLOADS=0
NON_INTERACTIVE=0
INSTALL_APP=0
REQUIRE_APP=0
INSTALL_DEV_TOOLS=0

OS_FAMILY=""
OS_NAME=""
OS_VERSION=""
ARCH=""
LINUX_ID=""
LINUX_VERSION_ID=""
LINUX_APP_FORMAT=""
LINUX_APP_REASON=""
WORK_DIR=""
LOG_FILE=""
CODEX_BIN=""
NPM_ENV=()
BOOTSTRAP_SOURCE=""

usage() {
  cat <<'EOF'
用法：
  install-codex-unix.sh [选项]

选项：
  --update                    更新 Codex CLI；默认仍使用官方 standalone 安装器
  --release VERSION           安装指定版本（默认：latest）
  --method METHOD             standalone、brew 或 npm（默认：standalone）
  --network MODE              auto、official 或 github（默认：auto）
  --check-only                仅做只读预检，不安装、不创建用户目录或日志
  --verify-downloads          实际下载并检查官方 standalone bootstrap
  --non-interactive           禁用官方安装器的交互提示
  --install-app               CLI 成功后调用当前 codex app 官方流程
  --skip-app                  跳过桌面应用（Linux 薄入口默认会请求安装）
  --require-app               要求 app 流程成功；同时启用 --install-app
  --install-dev-tools         检查 Git；macOS 启动 CLT，Linux 给出系统包命令
  --help, -h                  显示帮助

可选环境变量：
  CODEX_BOOTSTRAP_SHA256      固定 bootstrap 的 64 位 SHA-256
  CODEX_BOOTSTRAP_URL         企业镜像地址；严格 HTTPS 且必须同时提供 SHA-256 pin
  CODEX_NETWORK_MODE          auto、official 或 github；自定义 bootstrap URL 时忽略
  CODEX_INSTALL_DIR           官方 standalone 安装器的 CLI 目录
  CODEX_NPM_REGISTRY          npm 命令本次使用的 HTTPS registry
  CODEX_NPM_PREFIX            npm 命令本次使用的绝对 prefix

安全边界：
  默认不会安装 Git、Node.js、Python、Skills 或桌面 App，也不会写入
  config.toml/auth.json、处理 API Key、移除 quarantine，或安装 Homebrew。
EOF
}

step() {
  printf '\n========== %s ==========\n' "$1"
}

info() {
  printf '%s\n' "$1"
}

warn() {
  printf '警告：%s\n' "$1" >&2
}

die() {
  printf '错误：%s\n' "$1" >&2
  if [ -n "$LOG_FILE" ]; then
    printf '私有日志：%s\n' "$LOG_FILE" >&2
  fi
  exit 1
}

cleanup() {
  local status=$?
  trap - EXIT
  if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR" || true
  fi
  exit "$status"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

require_value() {
  [ "$#" -ge 2 ] && [ -n "$2" ] || die "$1 需要一个参数。"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --update)
        UPDATE=1
        ;;
      --release)
        require_value "$@"
        RELEASE="$2"
        shift
        ;;
      --release=*)
        RELEASE="${1#*=}"
        [ -n "$RELEASE" ] || die "--release 需要一个参数。"
        ;;
      --method)
        require_value "$@"
        METHOD="$2"
        shift
        ;;
      --method=*)
        METHOD="${1#*=}"
        [ -n "$METHOD" ] || die "--method 需要一个参数。"
        ;;
      --network)
        require_value "$@"
        NETWORK_MODE="$2"
        shift
        ;;
      --network=*)
        NETWORK_MODE="${1#*=}"
        [ -n "$NETWORK_MODE" ] || die "--network 需要一个参数。"
        ;;
      --check-only)
        CHECK_ONLY=1
        ;;
      --verify-downloads)
        VERIFY_DOWNLOADS=1
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        ;;
      --install-app)
        INSTALL_APP=1
        ;;
      --skip-app)
        INSTALL_APP=0
        REQUIRE_APP=0
        ;;
      --require-app)
        REQUIRE_APP=1
        INSTALL_APP=1
        ;;
      --install-dev-tools)
        INSTALL_DEV_TOOLS=1
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      --)
        shift
        [ "$#" -eq 0 ] || die "不接受位置参数：$1"
        break
        ;;
      -*)
        die "未知参数：$1。请运行 --help 查看支持的选项。"
        ;;
      *)
        die "不接受位置参数：$1"
        ;;
    esac
    shift
  done
}

validate_release() {
  if ! printf '%s\n' "$RELEASE" |
    LC_ALL=C grep -Eq '^(latest|[0-9]+\.[0-9]+\.[0-9]+(-alpha(\.[0-9]+){0,2}|-beta(\.[0-9]+)?)?)$'; then
    die "无效版本：$RELEASE。请使用 latest 或官方支持的语义化版本。"
  fi
}

validate_https_url() {
  local url="$1"
  local label="$2"
  local require_path="${3:-0}"
  local rest authority

  case "$url" in
    https://*)
      ;;
    *)
      die "$label 必须是 HTTPS URL。"
      ;;
  esac

  rest="${url#https://}"
  authority="${rest%%/*}"
  [ -n "$authority" ] || die "$label 缺少主机名。"
  if [ "$require_path" = "1" ]; then
    case "$rest" in
      */?*)
        ;;
      *)
        die "$label 必须包含非空路径。"
        ;;
    esac
  fi

  case "$authority" in
    *@*)
      die "$label 不允许 URL 用户信息。"
      ;;
  esac

  case "$url" in
    *' '*|*'	'*|*$'\n'*|*$'\r'*|*'\'*|*'?'*|*'#'*)
      die "$label 包含不允许的字符、查询参数或片段。"
      ;;
  esac
}

validate_options() {
  case "$METHOD" in
    standalone|brew|npm)
      ;;
    *)
      die "--method 仅支持 standalone、brew 或 npm。"
      ;;
  esac

  case "$NETWORK_MODE" in
    auto|official|github)
      ;;
    *)
      die "--network 仅支持 auto、official 或 github。"
      ;;
  esac

  validate_release
  validate_https_url "$BOOTSTRAP_URL" "CODEX_BOOTSTRAP_URL" 1

  if [ -n "${CODEX_BOOTSTRAP_SHA256:-}" ] &&
    ! printf '%s\n' "$CODEX_BOOTSTRAP_SHA256" |
      LC_ALL=C grep -Eq '^[0-9A-Fa-f]{64}$'; then
    die "CODEX_BOOTSTRAP_SHA256 必须是 64 位十六进制值。"
  fi

  if [ "$BOOTSTRAP_URL" != "$OFFICIAL_BOOTSTRAP_URL" ] &&
    [ "$BOOTSTRAP_URL" != "$OFFICIAL_BOOTSTRAP_ENTRY_URL" ] &&
    [ -z "${CODEX_BOOTSTRAP_SHA256:-}" ]; then
    die "非官方 CODEX_BOOTSTRAP_URL 必须同时提供 CODEX_BOOTSTRAP_SHA256 pin。"
  fi

  if [ "$METHOD" = "brew" ] && [ "$RELEASE" != "latest" ]; then
    die "Homebrew cask 不支持由本脚本固定任意版本；请改用 --method standalone 或 npm。"
  fi

  if [ -n "${CODEX_NPM_REGISTRY:-}" ]; then
    validate_https_url "$CODEX_NPM_REGISTRY" "CODEX_NPM_REGISTRY" 0
  fi

  if [ -n "${CODEX_INSTALL_DIR:-}" ]; then
    case "$CODEX_INSTALL_DIR" in
      /*)
        ;;
      *)
        die "CODEX_INSTALL_DIR 必须是绝对路径。"
        ;;
    esac
  fi

  if [ -n "${CODEX_NPM_PREFIX:-}" ]; then
    case "$CODEX_NPM_PREFIX" in
      /*)
        ;;
      *)
        die "CODEX_NPM_PREFIX 必须是绝对路径。"
        ;;
    esac
  fi

  if { [ -n "${CODEX_TEST_UNAME_S:-}" ] || [ -n "${CODEX_TEST_OS:-}" ] ||
    [ -n "${CODEX_TEST_ARCH:-}" ] || [ -n "${CODEX_TEST_OS_VERSION:-}" ] ||
    [ -n "${CODEX_TEST_LINUX_ID:-}" ] ||
    [ -n "${CODEX_TEST_LINUX_VERSION_ID:-}" ]; } &&
    [ "$CHECK_ONLY" != "1" ]; then
    die "CODEX_TEST_* 仅允许与 --check-only 一起使用。"
  fi
}

linux_pretty_name() {
  if [ -n "${CODEX_TEST_OS_VERSION:-}" ]; then
    printf '%s\n' "$CODEX_TEST_OS_VERSION"
    return
  fi

  if [ -r /etc/os-release ]; then
    sed -n 's/^PRETTY_NAME=//p' /etc/os-release |
      sed -n '1{s/^"//;s/"$//;p;}'
    return
  fi

  uname -r
}

detect_platform() {
  local raw_os raw_arch

  raw_os="${CODEX_TEST_UNAME_S:-${CODEX_TEST_OS:-$(uname -s)}}"
  raw_arch="${CODEX_TEST_ARCH:-$(uname -m)}"

  case "$raw_os" in
    Darwin|darwin|macOS|macos)
      OS_FAMILY="darwin"
      OS_NAME="macOS"
      if [ -n "${CODEX_TEST_OS_VERSION:-}" ]; then
        OS_VERSION="$CODEX_TEST_OS_VERSION"
      elif command -v sw_vers >/dev/null 2>&1; then
        OS_VERSION="$(sw_vers -productVersion)"
      else
        OS_VERSION="未知"
      fi
      ;;
    Linux|linux)
      OS_FAMILY="linux"
      OS_NAME="Linux"
      OS_VERSION="$(linux_pretty_name)"
      ;;
    *)
      die "不支持的系统：$raw_os。此脚本仅支持 macOS 和 Linux。"
      ;;
  esac

  case "$raw_arch" in
    x86_64|amd64|x64)
      ARCH="x64"
      ;;
    arm64|aarch64)
      ARCH="arm64"
      ;;
    *)
      die "不支持的 CPU 架构：$raw_arch。仅支持 x64 和 arm64。"
      ;;
  esac

  if [ "$OS_FAMILY" = "darwin" ] && [ "$ARCH" = "x64" ] &&
    [ -z "${CODEX_TEST_ARCH:-}" ] &&
    [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || true)" = "1" ]; then
    ARCH="arm64"
  fi
}

read_os_release_value() {
  local key="$1"
  local value=""
  [ -r /etc/os-release ] || return 0
  value="$(sed -n "s/^${key}=//p" /etc/os-release | sed -n '1p')"
  case "$value" in
    \"*\")
      value="${value#\"}"
      value="${value%\"}"
      ;;
  esac
  printf '%s\n' "$value"
}

detect_linux_app_support() {
  [ "$OS_FAMILY" = "linux" ] || return 0

  LINUX_ID="${CODEX_TEST_LINUX_ID:-$(read_os_release_value ID)}"
  LINUX_VERSION_ID="${CODEX_TEST_LINUX_VERSION_ID:-$(read_os_release_value VERSION_ID)}"
  LINUX_ID="$(printf '%s' "$LINUX_ID" | LC_ALL=C tr 'A-Z' 'a-z')"

  case "$LINUX_ID:$LINUX_VERSION_ID" in
    ubuntu:24.04|ubuntu:26.04|debian:13)
      LINUX_APP_FORMAT="deb"
      ;;
    fedora:43|fedora:44)
      LINUX_APP_FORMAT="rpm"
      ;;
    *)
      LINUX_APP_REASON="官方 Linux 桌面预览暂仅支持 Ubuntu 24.04/26.04、Debian 13、Fedora 43/44；当前为 ${LINUX_ID:-未知} ${LINUX_VERSION_ID:-未知}。"
      ;;
  esac
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "缺少必需命令：$1"
}

has_sha256_tool() {
  command -v sha256sum >/dev/null 2>&1 ||
    command -v shasum >/dev/null 2>&1 ||
    command -v openssl >/dev/null 2>&1
}

check_prerequisites() {
  step "依赖预检"
  require_command grep
  require_command sed
  require_command tr

  case "$METHOD" in
    standalone)
      require_command curl
      require_command mktemp
      require_command chmod
      require_command mv
      require_command wc
      require_command head
      require_command tar
      require_command awk
      require_command rm
      [ -x /bin/sh ] || die "缺少可执行的 /bin/sh。"
      has_sha256_tool || die "需要 sha256sum、shasum 或 openssl 来校验下载。"
      info "standalone 所需系统命令已就绪。"
      ;;
    brew)
      [ "$OS_FAMILY" = "darwin" ] ||
        die "--method brew 当前仅支持 macOS 的官方 codex cask。"
      require_command brew
      info "已检测到 Homebrew；本脚本不会自动安装 Homebrew。"
      ;;
    npm)
      require_command node
      require_command npm
      info "已检测到 Node.js 和 npm；本脚本不会自动安装或升级它们。"
      ;;
  esac

  if [ "$CHECK_ONLY" != "1" ]; then
    require_command mktemp
    require_command chmod
    require_command tee
  fi

}

show_plan() {
  local action="安装"
  [ "$UPDATE" = "1" ] && action="更新"

  step "${action}计划"
  info "系统：$OS_NAME $OS_VERSION"
  info "架构：$ARCH"
  info "安装方法：$METHOD"
  info "网络模式：$NETWORK_MODE"
  info "目标版本：$RELEASE"
  if [ "$METHOD" = "standalone" ]; then
    if [ "$BOOTSTRAP_URL" != "$OFFICIAL_BOOTSTRAP_URL" ] &&
      [ "$BOOTSTRAP_URL" != "$OFFICIAL_BOOTSTRAP_ENTRY_URL" ]; then
      info "bootstrap：$BOOTSTRAP_URL（组织自定义并要求 SHA-256 pin）"
    elif [ "$NETWORK_MODE" = "auto" ]; then
      info "bootstrap：优先 OpenAI CDN；短时不可用时自动切换 OpenAI GitHub Release"
    elif [ "$NETWORK_MODE" = "github" ]; then
      info "bootstrap：OpenAI GitHub Release"
    else
      info "bootstrap：$BOOTSTRAP_URL"
    fi
    info "bootstrap 将先下载到 0700 随机临时目录，检查后再执行（不会 pipe-to-sh）。"
  fi
  if [ "$INSTALL_APP" = "1" ]; then
    if [ "$OS_FAMILY" = "linux" ] && [ -n "$LINUX_APP_FORMAT" ]; then
      info "桌面端：官方 Linux ${LINUX_APP_FORMAT} 包（${LINUX_ID} ${LINUX_VERSION_ID}）"
    elif [ "$OS_FAMILY" = "linux" ]; then
      info "桌面端：将跳过；$LINUX_APP_REASON"
    else
      info "桌面端：CLI 成功后调用当前 codex app 官方流程"
    fi
  else
    info "桌面端：不安装"
  fi
  if [ "$INSTALL_DEV_TOOLS" = "1" ]; then
    info "开发工具：检查 Git；不安装 Node.js 或 Python"
  else
    info "开发工具：不安装"
  fi
  info "不会写入 Codex 配置/认证、处理 API Key、安装 Skills 或移除 quarantine。"
}

temporary_base() {
  local base="${TMPDIR:-/tmp}"
  base="${base%/}"
  if [ -z "$base" ] || [ ! -d "$base" ] || [ ! -w "$base" ]; then
    base="/tmp"
  fi
  printf '%s\n' "$base"
}

ensure_work_dir() {
  local base
  [ -n "$WORK_DIR" ] && return
  base="$(temporary_base)"
  WORK_DIR="$(mktemp -d "$base/codex-installer.XXXXXXXX")" ||
    die "无法创建随机临时目录。"
  chmod 700 "$WORK_DIR" || die "无法将临时目录权限设置为 0700。"
}

start_private_log() {
  local base
  base="$(temporary_base)"
  LOG_FILE="$(mktemp "$base/codex-install-log.XXXXXXXX")" ||
    die "无法创建随机私有日志。"
  chmod 600 "$LOG_FILE" || die "无法将日志权限设置为 0600。"
  exec > >(tee -a "$LOG_FILE") 2>&1
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file" | awk '{print $NF}'
  else
    return 1
  fi
}

validate_bootstrap() {
  local file="$1"
  local bytes first_line actual expected

  if [ ! -f "$file" ]; then
    warn "bootstrap 下载后不存在。"
    return 1
  fi
  bytes="$(wc -c <"$file" | tr -d '[:space:]')"
  case "$bytes" in
    ''|*[!0-9]*)
      warn "无法判断 bootstrap 大小。"
      return 1
      ;;
  esac
  if [ "$bytes" -lt "$BOOTSTRAP_MIN_BYTES" ]; then
    warn "bootstrap 仅 $bytes 字节，疑似错误页或截断响应。"
    return 1
  fi
  if [ "$bytes" -gt "$BOOTSTRAP_MAX_BYTES" ]; then
    warn "bootstrap 达到 $bytes 字节，超过安全上限。"
    return 1
  fi

  first_line="$(head -n 1 "$file")"
  case "$first_line" in
    '#!'*sh*)
      ;;
    *)
      warn "bootstrap 没有预期的 shell shebang。"
      return 1
      ;;
  esac

  if ! LC_ALL=C grep -Iq '^' "$file"; then
    warn "bootstrap 不是文本 shell 脚本。"
    return 1
  fi
  if ! grep -q 'CODEX_RELEASE' "$file"; then
    warn "bootstrap 缺少预期的 CODEX_RELEASE 标识。"
    return 1
  fi
  if ! grep -q -- '--release' "$file"; then
    warn "bootstrap 缺少预期的 --release 接口。"
    return 1
  fi
  if ! grep -q 'Codex CLI' "$file"; then
    warn "bootstrap 缺少预期的 Codex CLI 标识。"
    return 1
  fi

  if ! actual="$(sha256_file "$file")"; then
    warn "无法计算 bootstrap SHA-256。"
    return 1
  fi
  actual="$(printf '%s' "$actual" | LC_ALL=C tr 'A-F' 'a-f')"
  info "bootstrap SHA-256：$actual"

  if [ -n "${CODEX_BOOTSTRAP_SHA256:-}" ]; then
    expected="$(printf '%s' "$CODEX_BOOTSTRAP_SHA256" |
      LC_ALL=C tr 'A-F' 'a-f')"
    if ! printf '%s\n' "$expected" |
      LC_ALL=C grep -Eq '^[0-9a-f]{64}$'; then
      warn "CODEX_BOOTSTRAP_SHA256 必须是 64 位十六进制值。"
      return 1
    fi
    if [ "$actual" != "$expected" ]; then
      warn "bootstrap SHA-256 与 CODEX_BOOTSTRAP_SHA256 不一致。"
      return 1
    fi
    info "bootstrap SHA-256 pin 校验通过。"
  fi
  return 0
}

github_bootstrap_url() {
  # bootstrap 始终取最新官方 installer；CLI 目标版本仍由 --release 独立控制。
  printf '%s\n' "$GITHUB_BOOTSTRAP_LATEST_URL"
}

download_bootstrap_candidate() {
  local url="$1"
  local target="$2"
  local connect_timeout="$3"
  local max_time="$4"
  local max_attempts="$5"
  local part bytes attempt=1

  while [ "$attempt" -le "$max_attempts" ]; do
    part="$WORK_DIR/install.sh.part.$attempt"
    if curl \
        --disable \
        --proto '=https' \
        --proto-redir '=https' \
        --fail \
        --silent \
        --show-error \
        --location \
        --connect-timeout "$connect_timeout" \
        --max-time "$max_time" \
        "$url" |
      head -c "$((BOOTSTRAP_MAX_BYTES + 1))" >"$part"; then
      mv "$part" "$target" ||
        die "无法将已下载 bootstrap 移入私有目标路径。"
      chmod 600 "$target" || die "无法设置 bootstrap 私有权限。"
      if validate_bootstrap "$target"; then
        return 0
      fi
      warn "当前 bootstrap 候选未通过校验，尝试下一候选或重试。"
      rm -f "$target"
      attempt=$((attempt + 1))
      continue
    fi

    bytes="$(wc -c <"$part" | tr -d '[:space:]' || true)"
    if [ -n "$bytes" ] && [ "$bytes" -gt "$BOOTSTRAP_MAX_BYTES" ]; then
      warn "bootstrap 候选下载超过安全上限 $BOOTSTRAP_MAX_BYTES 字节，已拒绝该来源。"
      rm -f "$part"
      return 1
    fi
    rm -f "$part"
    attempt=$((attempt + 1))
  done
  return 1
}

download_bootstrap() {
  local target github_url
  ensure_work_dir
  target="$WORK_DIR/install.sh"

  step "下载并检查官方 bootstrap"
  # 自定义企业入口只使用已明确配置并固定摘要的 URL，不隐式绕过组织策略。
  if [ "$BOOTSTRAP_URL" != "$OFFICIAL_BOOTSTRAP_URL" ] &&
    [ "$BOOTSTRAP_URL" != "$OFFICIAL_BOOTSTRAP_ENTRY_URL" ]; then
    download_bootstrap_candidate "$BOOTSTRAP_URL" "$target" 20 180 4 ||
      die "连续 4 次无法从严格 HTTPS 地址下载 bootstrap：$BOOTSTRAP_URL"
    BOOTSTRAP_SOURCE="custom"
  elif [ "$NETWORK_MODE" = "github" ]; then
    github_url="$(github_bootstrap_url)"
    download_bootstrap_candidate "$github_url" "$target" 15 180 4 ||
      die "连续 4 次无法从 OpenAI GitHub Release 下载 bootstrap。"
    BOOTSTRAP_SOURCE="github"
  elif [ "$NETWORK_MODE" = "official" ]; then
    download_bootstrap_candidate "$BOOTSTRAP_URL" "$target" 20 180 4 ||
      die "连续 4 次无法从 OpenAI 官方 CDN 下载 bootstrap。"
    BOOTSTRAP_SOURCE="releases"
  elif download_bootstrap_candidate "$BOOTSTRAP_URL" "$target" 5 15 1; then
    BOOTSTRAP_SOURCE="releases"
  else
    warn "OpenAI CDN 快速探测未通过，自动切换 OpenAI GitHub Release，避免等待长超时。"
    github_url="$(github_bootstrap_url)"
    if download_bootstrap_candidate "$github_url" "$target" 10 90 3; then
      BOOTSTRAP_SOURCE="github"
    else
      warn "OpenAI GitHub Release 也未快速完成，最后重试 OpenAI CDN。"
      download_bootstrap_candidate "$BOOTSTRAP_URL" "$target" 20 180 3 ||
        die "OpenAI CDN 与 OpenAI GitHub Release 均无法下载 bootstrap；请检查代理、DNS 或企业 CA。"
      BOOTSTRAP_SOURCE="releases"
    fi
  fi

  info "bootstrap 来源：$(if [ "$BOOTSTRAP_SOURCE" = "github" ]; then printf 'OpenAI GitHub Release'; elif [ "$BOOTSTRAP_SOURCE" = "releases" ]; then printf 'OpenAI CDN'; else printf '组织自定义入口'; fi)"
}

linux_git_command() {
  if command -v apt-get >/dev/null 2>&1; then
    printf 'sudo apt-get update && sudo apt-get install -y git\n'
  elif command -v dnf >/dev/null 2>&1; then
    printf 'sudo dnf install -y git\n'
  elif command -v yum >/dev/null 2>&1; then
    printf 'sudo yum install -y git\n'
  elif command -v zypper >/dev/null 2>&1; then
    printf 'sudo zypper install git\n'
  elif command -v pacman >/dev/null 2>&1; then
    printf 'sudo pacman -S --needed git\n'
  elif command -v apk >/dev/null 2>&1; then
    printf 'sudo apk add git\n'
  else
    printf '请使用当前 Linux 发行版的官方系统包管理器安装 git。\n'
  fi
}

handle_dev_tools() {
  local git_path=""
  local git_version=""
  local git_ready=0

  [ "$INSTALL_DEV_TOOLS" = "1" ] || return 0

  step "开发工具"
  git_path="$(command -v git 2>/dev/null || true)"
  if [ -n "$git_path" ]; then
    git_ready=1
    if [ "$OS_FAMILY" = "darwin" ] && [ "$git_path" = "/usr/bin/git" ] &&
      command -v xcode-select >/dev/null 2>&1 &&
      ! xcode-select -p >/dev/null 2>&1; then
      # /usr/bin/git is only an Apple shim until CLT/Xcode is selected.
      git_ready=0
    fi
  fi

  if [ "$git_ready" = "1" ] &&
    git_version="$("$git_path" --version 2>/dev/null)"; then
    info "$git_version"
    return 0
  fi

  if [ "$OS_FAMILY" = "darwin" ]; then
    if [ "$CHECK_ONLY" = "1" ]; then
      info "未检测到 Git；实际运行时将调用 xcode-select --install 启动 Apple CLT 官方流程。"
    elif command -v xcode-select >/dev/null 2>&1; then
      if xcode-select --install >/dev/null 2>&1; then
        warn "已启动 Apple Command Line Tools 安装。完成后可重新运行本脚本确认 Git。"
      else
        warn "Apple CLT 可能已在安装、被策略阻止或需要手动执行：xcode-select --install"
      fi
    else
      warn "系统缺少 xcode-select；请通过 Apple 官方方式安装 Command Line Tools。"
    fi
  else
    info "未检测到 Git。请按需复制以下系统包管理器命令："
    linux_git_command
  fi
}

prepare_npm_env() {
  NPM_ENV=()
  if [ -n "${CODEX_NPM_REGISTRY:-}" ]; then
    NPM_ENV+=("npm_config_registry=$CODEX_NPM_REGISTRY")
  fi
  if [ -n "${CODEX_NPM_PREFIX:-}" ]; then
    NPM_ENV+=("npm_config_prefix=$CODEX_NPM_PREFIX")
  fi
  if [ "$NON_INTERACTIVE" = "1" ]; then
    NPM_ENV+=("npm_config_yes=true")
  fi
}

npm_command() {
  if [ "${#NPM_ENV[@]}" -gt 0 ]; then
    env "${NPM_ENV[@]}" npm "$@"
  else
    npm "$@"
  fi
}

install_standalone() {
  local args=()
  local installer_env=()
  args+=(--release "$RELEASE")

  [ -f "$WORK_DIR/install.sh" ] || download_bootstrap
  step "执行官方 standalone 安装器"
  if [ "$BOOTSTRAP_SOURCE" = "github" ]; then
    installer_env+=("CODEX_INSTALLER_USE_RELEASES_OPENAI_COM=false")
    info "已根据网络探测直接使用 OpenAI GitHub Release 资产，跳过不可用 CDN 的等待。"
  elif [ "$BOOTSTRAP_SOURCE" = "releases" ]; then
    installer_env+=("CODEX_INSTALLER_USE_RELEASES_OPENAI_COM=true")
    info "已根据网络模式固定使用 OpenAI CDN，不继承外部 GitHub Release 偏好。"
  fi
  if [ "$NON_INTERACTIVE" = "1" ]; then
    installer_env+=("CODEX_NON_INTERACTIVE=1")
  fi
  if [ "${#installer_env[@]}" -gt 0 ]; then
    env "${installer_env[@]}" /bin/sh "$WORK_DIR/install.sh" "${args[@]}"
  else
    /bin/sh "$WORK_DIR/install.sh" "${args[@]}"
  fi
}

install_brew() {
  step "通过 Homebrew 安装 Codex CLI"
  if [ "$UPDATE" = "1" ] && brew list --cask codex >/dev/null 2>&1; then
    env HOMEBREW_NO_ENV_HINTS=1 brew upgrade --cask codex
  elif brew list --cask codex >/dev/null 2>&1; then
    info "Homebrew codex cask 已安装；使用 --update 可检查更新。"
  else
    env HOMEBREW_NO_ENV_HINTS=1 brew install --cask codex
  fi
}

install_npm() {
  local package="@openai/codex@$RELEASE"
  step "通过 npm 安装 Codex CLI"
  prepare_npm_env
  npm_command install --global "$package"
}

resolve_codex_bin() {
  local candidate=""
  local prefix=""

  case "$METHOD" in
    standalone)
      if [ -n "${CODEX_INSTALL_DIR:-}" ]; then
        candidate="$CODEX_INSTALL_DIR/codex"
      elif [ -n "${HOME:-}" ]; then
        candidate="$HOME/.local/bin/codex"
      fi
      ;;
    brew)
      prefix="$(brew --prefix 2>/dev/null || true)"
      [ -n "$prefix" ] && candidate="$prefix/bin/codex"
      ;;
    npm)
      if [ -n "${CODEX_NPM_PREFIX:-}" ]; then
        candidate="$CODEX_NPM_PREFIX/bin/codex"
      else
        prepare_npm_env
        prefix="$(npm_command prefix --global 2>/dev/null | sed -n '$p' || true)"
        [ -n "$prefix" ] && candidate="$prefix/bin/codex"
      fi
      ;;
  esac

  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

verify_codex() {
  local version_output path_codex expected_version expected_pattern codex_dir
  hash -r
  if ! CODEX_BIN="$(resolve_codex_bin)"; then
    die "安装命令结束，但找不到可执行的 codex。"
  fi

  step "安装后验证"
  if ! version_output="$("$CODEX_BIN" --version 2>&1)"; then
    die "codex --version 验证失败：$version_output"
  fi
  [ -n "$version_output" ] || die "codex --version 没有返回版本信息。"
  info "本次安装目标：$CODEX_BIN"
  info "$version_output"

  expected_version="$RELEASE"
  expected_version="${expected_version#rust-v}"
  expected_version="${expected_version#v}"
  if [ "$expected_version" != "latest" ]; then
    expected_pattern="$(printf '%s' "$expected_version" | sed 's/\./\\./g')"
    if ! printf '%s\n' "$version_output" |
      LC_ALL=C grep -Eq "(^|[^0-9A-Za-z])v?${expected_pattern}([^0-9A-Za-z.+-]|$)"; then
      die "本次目标版本与请求版本不一致。请求：$expected_version；实际：$version_output"
    fi
    info "请求版本与本次安装目标一致：$expected_version"
  fi

  path_codex="$(command -v codex 2>/dev/null || true)"
  if [ -n "$path_codex" ]; then
    if [ ! -x "$path_codex" ] || [ ! "$path_codex" -ef "$CODEX_BIN" ]; then
      die "本次目标已安装并验证，但当前 PATH 优先解析到其他 Codex：$path_codex。请重新打开终端，使 $CODEX_BIN 优先后再重试。"
    fi
  else
    codex_dir="$(cd -P "$(dirname "$CODEX_BIN")" && pwd)"
    PATH="$codex_dir:$PATH"
    export PATH
    hash -r
  fi

  if "$CODEX_BIN" doctor --summary --no-color --ascii; then
    info "codex doctor 检查完成。"
  else
    warn "codex doctor 未通过或当前版本不提供该命令；CLI 版本验证已通过，此项仅作建议。"
  fi
}

install_app() {
  [ "$INSTALL_APP" = "1" ] || return 0

  if [ "$OS_FAMILY" = "linux" ]; then
    if [ -z "$LINUX_APP_FORMAT" ]; then
      if [ "$REQUIRE_APP" = "1" ]; then
        die "$LINUX_APP_REASON"
      fi
      warn "PARTIAL：$LINUX_APP_REASON CLI 已安装并验证。"
      return
    fi
    # App 是可选组件时在子 shell 中隔离 die/exit；关闭子 shell 的 EXIT
    # trap，避免一次 App 失败提前删除主流程仍需保留的日志和工作目录。
    if (trap - EXIT; install_linux_app); then
      return
    fi
    if [ "$REQUIRE_APP" = "1" ]; then
      die "CLI 已安装，但必需的 ChatGPT Linux 桌面应用安装失败。"
    fi
    warn "PARTIAL：Codex CLI 已安装并验证，但 ChatGPT Linux 桌面应用未完成。"
    return
  fi

  step "Codex 桌面端官方流程"
  if "$CODEX_BIN" app; then
    info "codex app 官方流程已成功启动/完成。"
    return
  fi

  if [ "$REQUIRE_APP" = "1" ]; then
    die "CLI 已安装，但必需的 codex app 官方流程失败。"
  fi
  warn "PARTIAL：Codex CLI 已安装并验证，但 codex app 官方流程失败。"
}

linux_app_url() {
  if [ "$LINUX_APP_FORMAT" = "deb" ] && [ "$ARCH" = "x64" ]; then
    printf 'https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb\n'
  elif [ "$LINUX_APP_FORMAT" = "deb" ]; then
    printf 'https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_arm64.deb\n'
  elif [ "$ARCH" = "x64" ]; then
    printf 'https://persistent.oaistatic.com/codex-app-prod/linux/rpm/latest/chatgpt.x86_64.rpm\n'
  else
    printf 'https://persistent.oaistatic.com/codex-app-prod/linux/rpm/latest/chatgpt.aarch64.rpm\n'
  fi
}

download_linux_app() {
  local url="$1"
  local target="$2"
  local part bytes
  local attempt=1
  local download_ok

  step "下载 OpenAI 官方 ChatGPT Linux 桌面应用"
  while [ "$attempt" -le 4 ]; do
    part="$target.part.$attempt"
    download_ok=0
    if curl \
        --disable \
        --proto '=https' \
        --proto-redir '=https' \
        --fail \
        --silent \
        --show-error \
        --location \
        --connect-timeout 15 \
        --max-time 1800 \
        "$url" |
      head -c "$((LINUX_APP_MAX_BYTES + 1))" >"$part"; then
      download_ok=1
    fi
    bytes="$(wc -c <"$part" | tr -d '[:space:]')"
    if [ "$bytes" -gt "$LINUX_APP_MAX_BYTES" ]; then
      rm -f "$part"
      die "ChatGPT Linux 包超过安全上限：$bytes 字节。"
    fi
    if [ "$download_ok" = "1" ] &&
      [ "$bytes" -ge "$LINUX_APP_MIN_BYTES" ]; then
      mv "$part" "$target" || die "无法保存 ChatGPT Linux 包。"
      chmod 600 "$target" || die "无法设置 ChatGPT Linux 包私有权限。"
      info "官方桌面包下载完成：$bytes 字节。"
      return 0
    fi
    warn "ChatGPT Linux 包第 $attempt 次下载未完整通过，将使用全新临时文件重试。"
    rm -f "$part"
    attempt=$((attempt + 1))
  done
  return 1
}

run_privileged() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif [ "$NON_INTERACTIVE" = "1" ]; then
    sudo -n "$@"
  else
    sudo "$@"
  fi
}

validate_linux_app_package() {
  local target="$1"
  local name package_arch expected_arch

  if [ "$LINUX_APP_FORMAT" = "deb" ]; then
    name="$(dpkg-deb -f "$target" Package)"
    package_arch="$(dpkg-deb -f "$target" Architecture)"
    expected_arch="$(if [ "$ARCH" = "x64" ]; then printf 'amd64'; else printf 'arm64'; fi)"
  else
    name="$(rpm -qp --queryformat '%{NAME}' "$target")"
    package_arch="$(rpm -qp --queryformat '%{ARCH}' "$target")"
    expected_arch="$(if [ "$ARCH" = "x64" ]; then printf 'x86_64'; else printf 'aarch64'; fi)"
  fi

  [ "$name" = "chatgpt" ] || die "桌面包名称不匹配：$name"
  [ "$package_arch" = "$expected_arch" ] ||
    die "桌面包架构不匹配：期望 $expected_arch，实际 $package_arch"
  info "桌面包元数据校验通过：chatgpt / $package_arch。"
}

install_linux_app() {
  local url target

  step "ChatGPT Linux 桌面应用"
  require_command curl
  require_command id
  if [ "$LINUX_APP_FORMAT" = "deb" ]; then
    require_command dpkg-deb
    require_command apt
  else
    require_command rpm
    require_command dnf
  fi
  if [ "$(id -u)" -ne 0 ]; then
    require_command sudo
  fi

  ensure_work_dir
  url="$(linux_app_url)"
  target="$WORK_DIR/chatgpt.$LINUX_APP_FORMAT"
  download_linux_app "$url" "$target" ||
    die "无法从 OpenAI 官方 CDN 下载 ChatGPT Linux 桌面包。"
  validate_linux_app_package "$target"

  if [ "$LINUX_APP_FORMAT" = "deb" ]; then
    if ! run_privileged apt install -y "$target"; then
      die "apt 安装 ChatGPT Linux 桌面包失败。"
    fi
    dpkg-query -W -f='${Status}\n' chatgpt 2>/dev/null |
      grep -q '^install ok installed$' ||
      die "apt 结束后未确认 chatgpt 已安装。"
  else
    if ! run_privileged dnf install -y "$target"; then
      die "dnf 安装 ChatGPT Linux 桌面包失败。"
    fi
    rpm -q chatgpt >/dev/null 2>&1 ||
      die "dnf 结束后未确认 chatgpt 已安装。"
  fi
  info "ChatGPT Linux 桌面应用已安装；后续更新由其配置的 OpenAI 软件源提供。"
}

show_post_install_guide() {
  step "后续配置参考（安装器不会自动改配置）"
  info "个人配置：~/.codex/config.toml"
  info "项目配置：项目目录/.codex/config.toml（仅信任项目后加载）"
  cat <<'EOF'
打开并备份个人配置：
  mkdir -p ~/.codex
  [ ! -f ~/.codex/config.toml ] || cp ~/.codex/config.toml ~/.codex/config.toml.bak
  "${EDITOR:-vi}" ~/.codex/config.toml

安全起点示例：
  model = "gpt-5.6"
  model_reasoning_effort = "medium"
  approval_policy = "on-request"
  sandbox_mode = "workspace-write"

修改后验证：
  codex --strict-config --version
  codex doctor --summary

完整案例：docs/configuration.md
官方参考：https://learn.chatgpt.com/docs/config-file/config-basic
EOF
}

main() {
  parse_args "$@"
  validate_options
  detect_platform
  detect_linux_app_support
  check_prerequisites
  show_plan
  handle_dev_tools

  if [ "$CHECK_ONLY" = "1" ]; then
    if [ "$VERIFY_DOWNLOADS" = "1" ]; then
      if [ "$METHOD" = "standalone" ]; then
        download_bootstrap
        info "bootstrap 下载与内容校验通过；临时文件将在退出时清理。"
      else
        info "--verify-downloads：$METHOD 下载由对应包管理器负责，本脚本没有可预取文件。"
      fi
    fi
    step "只读预检完成"
    info "未执行安装，未创建用户目录或日志。"
    exit 0
  fi

  ensure_work_dir
  start_private_log

  case "$METHOD" in
    standalone)
      download_bootstrap
      install_standalone
      ;;
    brew)
      install_brew
      ;;
    npm)
      install_npm
      ;;
  esac

  verify_codex
  install_app
  show_post_install_guide

  step "完成"
  info "Codex CLI 已安装并通过 codex --version 验证。"
  info "私有日志：$LOG_FILE"
}

main "$@"
