# Codex / ChatGPT 跨平台一键安装器

[![Compatibility](https://github.com/seaworld008/codex-one-click-installer/actions/workflows/compatibility.yml/badge.svg)](https://github.com/seaworld008/codex-one-click-installer/actions/workflows/compatibility.yml)
[![Upstream smoke](https://github.com/seaworld008/codex-one-click-installer/actions/workflows/upstream-smoke.yml/badge.svg)](https://github.com/seaworld008/codex-one-click-installer/actions/workflows/upstream-smoke.yml)
[![Latest Release](https://img.shields.io/github/v/release/seaworld008/codex-one-click-installer?display_name=tag&sort=semver)](https://github.com/seaworld008/codex-one-click-installer/releases/latest)
[![License: MIT](https://img.shields.io/github/license/seaworld008/codex-one-click-installer)](LICENSE)
[![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-2ea44f)](#支持范围)

面向 Windows、macOS 和 Linux 的中文 Codex CLI 安装与更新入口，同时可选安装 ChatGPT 桌面应用和常用开发工具。

本项目是社区维护的便捷包装器，不是 OpenAI 官方安装器，也不代表 OpenAI。它不重新打包 Codex CLI，不内置来源不明的二进制，而是调用 [OpenAI 官方 Codex CLI 安装器](https://learn.chatgpt.com/docs/codex/cli)；产品能力、账号可用性和系统要求以官方文档为准。

## v2.0.0 的核心变化

- 改用 OpenAI 官方 standalone 安装器，Node.js 和 npm 不再是安装 Codex CLI 的前置条件。
- 新增 Linux x64 / Arm64 入口；macOS 继续支持 Intel 与 Apple Silicon。
- Windows 桌面端改用官方 ChatGPT Microsoft Store 产品 ID `9PLM9XGG6VKS`，不再使用模糊的 `Codex` 包名。
- 删除仓库内置 `Codex Installer.exe`、任意远程 Skills ZIP 和自定义 EXE 下载执行路径。
- 安装器不再读取 API Key，也不创建或覆盖 `~/.codex/auth.json`、`~/.codex/config.toml`。
- 不再递归清除 macOS Gatekeeper quarantine，不再永久修改 PowerShell ExecutionPolicy 或 npm 全局配置。
- Windows 8 / 8.1 不再支持；Windows 10 1809 及以上仅为尽力兼容，Windows 11 是推荐基线。
- Release 自动生成 ZIP、tar.gz、SHA256 校验文件和 SPDX SBOM，验证归档解包后的真实执行权限，并为资产生成 GitHub/Sigstore provenance 与 SBOM attestation。

完整变更见 [CHANGELOG.md](CHANGELOG.md)，从 v1.x 升级前请阅读 [v2 迁移指南](docs/migration-v2.md)。

当前 `Unreleased` 版本继续补齐：

- 默认 `auto` 网络模式先快速尝试 OpenAI CDN，异常时自动切换 OpenAI 官方 GitHub Release，并让官方 bootstrap 直接使用对应下载通道。
- Linux 薄入口默认同时安装官方 ChatGPT 桌面应用；自动识别官方支持的 Ubuntu、Debian、Fedora 版本与 x64/ARM64 包。
- 安装结束直接输出个人/项目配置位置、安全起点、验证命令和可复制的 [配置案例](docs/configuration.md)。

## 快速开始

从 [Releases](https://github.com/seaworld008/codex-one-click-installer/releases/latest) 下载最新版并校验 SHA256，解压后使用对应入口。

| 系统 | 首次安装 | 后续更新 | 默认行为 |
| --- | --- | --- | --- |
| Windows | 双击 `Windows双击安装Codex.cmd` | 双击 `Windows双击更新Codex.cmd` | 安装/更新 CLI，并尝试安装/更新桌面应用；开发工具必须显式选择 |
| macOS | 双击 `macOS双击安装Codex.command` | 双击 `macOS双击更新Codex.command` | 安装/更新 CLI，并打开官方桌面应用流程；开发工具必须显式选择 |
| Linux | `./install-codex-linux.sh` | `./install-codex-linux.sh --update` | 安装/更新 CLI，并在官方支持的桌面发行版上尝试安装/更新桌面应用 |

安装后重新打开终端，执行：

```bash
codex --version
codex
```

第一次运行 `codex` 时，按界面选择“使用 ChatGPT 登录”或其他可用的官方认证方式。安装脚本不会询问或写入你的密钥；私有安装日志会记录安装器及子进程输出，因此不要把凭据放进命令参数，公开日志前仍须脱敏。

## 支持范围

| 平台 | 架构 | 支持级别 | 说明 |
| --- | --- | --- | --- |
| Windows 11 | x64 / Arm64 | 推荐 | 原生 PowerShell 路径；桌面应用支持官方 Windows sandbox |
| Windows 10 1809+ | x64 | 尽力兼容 | CLI 最低 build 17763；桌面应用最低 build 19041，较旧 LTSC 会跳过桌面步骤 |
| macOS | Intel / Apple Silicon | 支持 | CLI 由官方 standalone 安装器选择正确架构 |
| Linux | x64 / Arm64 | 支持 | CLI 支持常见现代发行版；桌面应用预览支持 Ubuntu 24.04/26.04、Debian 13、Fedora 43/44 |
| Windows 8 / 8.1、32 位系统 | — | 不支持 | 已停止维护且不满足现代 Codex 安全与运行时基线 |

Windows 用户如果开发环境主要位于 WSL2，请参考 [OpenAI WSL 指南](https://learn.chatgpt.com/docs/windows/wsl)，并将仓库放在 Linux 文件系统（例如 `~/code`）以获得更好的性能。WSL1 已不再受现代 Codex 支持。

桌面应用的支持范围与 CLI 不完全相同，请分别参考 [ChatGPT 桌面应用](https://learn.chatgpt.com/docs/app)、[Windows 应用](https://learn.chatgpt.com/docs/windows/windows-app) 和 [Linux 应用](https://learn.chatgpt.com/docs/linux/linux-app)。

## 安全模型

默认 standalone 路径采用两层校验：

1. 本仓库优先从 `https://releases.openai.com/codex/install.sh` 或 `https://releases.openai.com/codex/install.ps1` 下载官方 bootstrap 到本次运行专属的临时目录，不使用 `curl | sh` 或 `irm | iex`。`auto` 模式快速失败时只回退到 `github.com/openai/codex` 的 OpenAI 官方 Release installer。
2. 官方 bootstrap 从 `releases.openai.com` 获取版本化元数据和 SHA256 清单，在 staging 中安装、自检并原子切换当前版本；官方源不可用时才按其自身逻辑回退 OpenAI 的 GitHub Release。

你还可以用 `CODEX_BOOTSTRAP_SHA256` 固定本次允许执行的 bootstrap 摘要。bootstrap 会随上游更新，因此固定摘要需要由组织自己的发布流程同步维护。

本项目的默认边界：

- 不写入或改写 Codex 配置、认证、模型、sandbox、网络访问和数据存储策略。
- 不安装远程 Skills 包；请使用 Codex 当前支持的 skills / plugins 管理流程。
- 不默认安装 Git、Node.js、Python、GitHub CLI 或系统包管理器；开发工具步骤必须显式选择。
- 不提交、不分发 EXE、MSI、PKG、DMG 或 Codex 本体。
- 不关闭 Gatekeeper，不降低 TLS 协议，不改变用户的全局 npm registry、prefix 或 PowerShell ExecutionPolicy。
- 桌面应用失败不会伪装成完整成功；CLI 成功但可选桌面应用失败会明确标记为“部分成功”。使用 require 参数可以把它提升为整体失败。

安全问题请不要公开粘贴利用细节或密钥，按 [SECURITY.md](SECURITY.md) 使用 GitHub 私密漏洞报告。

## Windows

### 双击入口

```text
Windows双击安装Codex.cmd
Windows双击更新Codex.cmd
```

安装入口默认执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-codex.ps1 `
  -InstallDesktopApp
```

更新入口默认执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-codex.ps1 `
  -Update -InstallDesktopApp
```

这里的 `ExecutionPolicy Bypass` 只作用于这一次 PowerShell 进程；脚本不会修改持久化 ExecutionPolicy。

### 常用参数

```powershell
# 默认：只安装/更新 Codex CLI
.\install-codex.ps1

# 指定版本；latest 为默认值
.\install-codex.ps1 -Release 0.149.1

# 默认自动选择更快的官方通道；也可强制指定
.\install-codex.ps1 -NetworkMode auto
.\install-codex.ps1 -NetworkMode github

# 同时安装/更新 ChatGPT 桌面应用
.\install-codex.ps1 -InstallDesktopApp

# 桌面应用失败时让整个流程失败
.\install-codex.ps1 -InstallDesktopApp -RequireDesktopApp

# 显式选择后，仅在缺失时通过 winget 补充 Git、Node.js、Python 3、GitHub CLI
.\install-codex.ps1 -InstallDevTools

# 显式使用 npm 兼容路径；不会永久修改 npm 配置
.\install-codex.ps1 -CliMethod npm -NpmRegistry https://registry.npmjs.org

# 只打印计划，不安装、不下载、不写用户目录
.\install-codex.ps1 -CheckOnly -NonInteractive -NoPause

# 下载并检查官方 bootstrap，但不安装
.\install-codex.ps1 -CheckOnly -VerifyDownloads -NonInteractive -NoPause
```

Windows 桌面应用优先使用：

```powershell
winget install --id 9PLM9XGG6VKS --exact -s msstore
```

也可以使用 OpenAI 官方文档链接的 [Microsoft Web Installer](https://get.microsoft.com/installer/download/9PLM9XGG6VKS)。

ChatGPT desktop app 的包清单最低要求 Windows build 19041。CLI 仍可在 build 17763+ 尽力运行；低于 19041 时，可选桌面步骤会明确标记为部分成功并跳过下载，`-RequireDesktopApp` 则在预检中失败。

如果 Microsoft Store / winget 不可用，脚本可以回退到 OpenAI 官方发布的架构固定、Store 签名 MSIX。脚本会先限制下载体积，再校验包清单中的 `OpenAI.Codex` identity、OpenAI Store publisher 与目标架构，随后执行 Authenticode 和 `Add-AppxPackage` 信任链/部署校验；脚本不会执行自定义 EXE。

## macOS

### 双击入口

```text
macOS双击安装Codex.command
macOS双击更新Codex.command
```

如果 Finder 首次阻止打开，请使用 macOS 提供的“右键 → 打开”确认来源，或在“系统设置 → 隐私与安全性”中查看拦截原因。不要运行递归 `xattr -dr` 绕过 Gatekeeper。

命令行方式：

```bash
chmod +x install-codex-unix.sh install-codex-macos.sh

./install-codex-macos.sh
./install-codex-macos.sh --update
./install-codex-macos.sh --install-app
./install-codex-macos.sh --install-dev-tools
```

桌面应用步骤调用当前 CLI 的 `codex app`，让 OpenAI 自己的流程处理应用下载与打开，仓库不硬编码或重新分发 DMG。

## Linux

```bash
chmod +x install-codex-unix.sh install-codex-linux.sh

./install-codex-linux.sh
./install-codex-linux.sh --update
./install-codex-linux.sh --release 0.149.1
./install-codex-linux.sh --skip-app
```

Linux 薄入口默认请求安装桌面应用。脚本会识别官方支持的发行版，下载有体积上限的官方 `.deb` / `.rpm`，校验 `chatgpt` 包名和目标架构后交给 `apt` / `dnf`；不支持的桌面发行版会保留已验证的 CLI 并报告部分成功。使用 `--skip-app` 可只安装 CLI。

脚本不会擅自使用 root 安装通用开发环境。Linux 使用 `--install-dev-tools` 时只会给出可复制的系统包命令，不会自动执行；macOS 只会在缺少 Git 时启动 Apple Command Line Tools 官方流程。

## Unix 通用参数

`install-codex-macos.sh` 和 `install-codex-linux.sh` 都是薄入口，实际逻辑位于 `install-codex-unix.sh`。

```text
--update
--release VERSION
--method standalone|brew|npm
--network auto|official|github
--install-app
--skip-app
--require-app
--install-dev-tools
--check-only
--verify-downloads
--non-interactive
--help
```

示例：

```bash
# Homebrew 已存在时显式使用 cask
./install-codex-macos.sh --method brew

# npm 已存在时显式使用 npm，不写 ~/.npmrc
CODEX_NPM_REGISTRY=https://registry.npmjs.org \
  ./install-codex-linux.sh --method npm

# 仅下载并检查官方 bootstrap
./install-codex-unix.sh --check-only --verify-downloads --non-interactive
```

## 网络自动判断与加速

默认 `auto` 不按 IP 或地区猜测用户位置，而是直接做小体积、短超时的真实可用性判断：

1. OpenAI CDN 能快速返回有效 bootstrap 时继续使用默认官方 CDN。
2. CDN 快速失败时，切换到 `github.com/openai/codex` 的 OpenAI 官方 Release installer，并设置官方 bootstrap 直接从相同 Release 通道下载，避免先等待 CDN 长超时。
3. 两个官方通道都未快速完成时，最后重试 CDN并给出代理、DNS、企业 CA 排查提示。

该流程不使用不明二进制镜像，不关闭 TLS，也不改变账号或服务的地区可用性。组织可以用 `--network official` 禁止 GitHub 回退，或用 `--network github` 显式选择 OpenAI 官方 GitHub Release。已有合规代理会通过当前进程的 `HTTPS_PROXY` / `HTTP_PROXY` / `NO_PROXY` 自动继承。

## 更新与安装来源迁移

官方 standalone 安装器会识别 npm / Bun 管理的旧 Codex，并提示 PATH 中可能存在多个安装来源。先确认新版本可用：

```bash
type -a codex
codex --version
codex doctor --summary
```

Windows PowerShell：

```powershell
Get-Command codex -All
codex --version
codex doctor --summary --no-color --ascii
```

本仓库会先验证本次安装方法推导出的确切可执行文件；指定非 `latest` 版本时还会比对实际版本。如果当前 PATH 仍优先解析到旧 Codex，流程会明确失败并要求重新打开终端，而不会拿旧命令冒充本次安装成功。

确认 standalone 路径优先且工作正常后，如不再需要旧 npm 版本，可自行执行：

```bash
npm uninstall -g @openai/codex
```

不要在验证新安装之前卸载旧版本。安装器也不会替你删除已有 npm、Homebrew、配置、认证或会话数据。

## 安装后的配置修改

安装结束会输出个人配置、项目配置、备份、编辑和验证命令。完整可复制案例见 [安装后的 Codex 配置参考](docs/configuration.md)。

最小安全起点：

```toml
model = "gpt-5.6"
model_reasoning_effort = "medium"
approval_policy = "on-request"
sandbox_mode = "workspace-write"
```

安装器不会自动创建或覆盖 `~/.codex/config.toml`。修改后运行：

```bash
codex --strict-config --version
codex doctor --summary
```

## 认证、代理与企业 CA

交互式使用建议直接运行：

```bash
codex
# 或
codex login
```

自动化场景请按 [官方认证文档](https://learn.chatgpt.com/docs/auth) 使用进程级凭据，避免把密钥写进仓库、脚本、Issue、日志或 shell history。

代理通常由当前进程继承：

```text
HTTPS_PROXY
HTTP_PROXY
NO_PROXY
```

如果组织使用 TLS 拦截或私有根证书：

- macOS / Linux 首次安装可由组织提供 PEM CA bundle，并在运行前设置 `CURL_CA_BUNDLE=/absolute/path/company-ca-bundle.pem`；该变量会同时作用于本仓库的 `curl` 和随后官方 bootstrap 使用的 `curl`。
- Windows 应由 IT 将组织根证书部署到 Windows 受信任根证书存储，使 PowerShell、Store 和 AppX 使用同一系统信任策略。
- `CODEX_CA_CERTIFICATE` 属于 Codex CLI 安装后的运行期网络配置，不能替代首次 bootstrap 下载所需的 curl/Windows 系统信任。

不要使用 `curl -k`、`NODE_TLS_REJECT_UNAUTHORIZED=0` 或关闭 PowerShell 证书校验。详见 [故障排查](docs/troubleshooting.md)。

## Release 校验

每个正式 Release 应包含：

- `codex-one-click-installer-vX.Y.Z.zip`
- `codex-one-click-installer-vX.Y.Z.tar.gz`
- `SHA256SUMS`
- SPDX JSON SBOM

macOS：

```bash
shasum -a 256 -c SHA256SUMS
```

Linux：

```bash
sha256sum -c SHA256SUMS
```

Windows PowerShell 可逐个比对：

```powershell
Get-FileHash .\codex-one-click-installer-v2.0.1.zip -Algorithm SHA256
Get-Content .\SHA256SUMS
```

ZIP 和 tar.gz 都会在发布流水线中重新解包验证；`.sh` / `.command` 必须保持 `0755`，从而避免 v1.2.0 曾出现的“Git 中可执行、发布包中不可执行”问题。

发布流水线还会为 `SHA256SUMS` 中的资产生成 GitHub artifact attestation。安装前可以额外验证来源：

```bash
gh attestation verify codex-one-click-installer-v2.0.1.zip \
  --repo seaworld008/codex-one-click-installer
```

## CI 与证据边界

- `Compatibility`：语法、静态规则、仓库测试、Windows PowerShell 5.1、Windows 10/11 计划、macOS/Linux 计划和发布打包测试。
- `Upstream smoke`：定期检查 OpenAI bootstrap、release metadata、npm 包和桌面应用 URL 是否仍可用。
- `Release`：要求 annotated tag 与 `VERSION` 一致、commit 已进入 `origin/main`，发布前后复核远端 tag；资产先进入 draft、下载回读校验并生成 provenance/SBOM attestation，最后才公开。已存在 Release 只允许摘要完全一致的幂等重跑，不覆盖公开资产。

CI 的 `CheckOnly` 通过只证明脚本解析和计划分支通过，不等于所有真实设备、代理、Store、登录或生产网络都已验证。正式兼容性声明仍应以真实 Windows/macOS/Linux 安装与 `codex --version` 结果为准。

## 开发与贡献

提交改动前运行：

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
bash -n install-codex-unix.sh install-codex-macos.sh install-codex-linux.sh
bash -n macOS双击安装Codex.command macOS双击更新Codex.command
./scripts/package-release.sh
git diff --check
```

Windows 还应使用 Windows PowerShell 5.1 解析并运行 `-CheckOnly`。完整要求见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 相关官方资料

- [Codex CLI](https://learn.chatgpt.com/docs/codex/cli)
- [ChatGPT 桌面应用](https://learn.chatgpt.com/docs/app)
- [Windows 桌面应用](https://learn.chatgpt.com/docs/windows/windows-app)
- [Linux 桌面应用](https://learn.chatgpt.com/docs/linux/linux-app)
- [Windows WSL](https://learn.chatgpt.com/docs/windows/wsl)
- [Codex 认证](https://learn.chatgpt.com/docs/auth)
- [Codex 配置](https://learn.chatgpt.com/docs/config-file/config-basic)
- [Codex 环境变量](https://learn.chatgpt.com/docs/config-file/environment-variables)

## License

本仓库脚本和文档使用 [MIT License](LICENSE)。Codex、ChatGPT 及其官方分发包遵循 OpenAI 各自的许可和服务条款；本仓库不对其重新授权。
