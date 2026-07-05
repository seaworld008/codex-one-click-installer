# Codex 跨平台一键安装器

[![Compatibility](https://github.com/seaworld008/codex-one-click-installer/actions/workflows/compatibility.yml/badge.svg)](https://github.com/seaworld008/codex-one-click-installer/actions/workflows/compatibility.yml)
[![Latest Release](https://img.shields.io/github/v/release/seaworld008/codex-one-click-installer?display_name=tag&sort=semver)](https://github.com/seaworld008/codex-one-click-installer/releases/latest)
[![License: MIT](https://img.shields.io/github/license/seaworld008/codex-one-click-installer)](LICENSE)
[![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20macOS-2ea44f)](#支持范围)
[![OpenAI Codex CLI](https://img.shields.io/badge/OpenAI-Codex%20CLI-412991)](https://github.com/seaworld008/codex-one-click-installer)
[![GitHub stars](https://img.shields.io/github/stars/seaworld008/codex-one-click-installer?style=social)](https://github.com/seaworld008/codex-one-click-installer/stargazers)

Windows / macOS one-click installer for OpenAI Codex CLI.

这个仓库提供 Windows 和 macOS 的 Codex CLI 一键安装脚本，适合希望快速安装 Codex CLI、又不想手动处理 Git / Node.js / Python / npm registry / 网络镜像的用户。脚本会优先使用官方可获取的安装包；当系统或架构不满足官方安装条件时，会在下载和安装前尽早提示用户。

如果这个项目帮到了你，欢迎 Star、转发给需要的人，或者在 Issues 里补充你的系统环境和安装结果，帮助更多用户少走弯路。

## 亮点

- 双击即可开始：Windows 使用 `.cmd`，macOS 使用 `.command`。
- 跨平台覆盖：Windows 10 / 11、部分 Windows 8 / 8.1 兼容路径、macOS x64 / Apple Silicon。
- 国内网络友好：默认使用 `npmmirror.com` 和 `registry.npmmirror.com`，失败时回退官方源。
- 预检优先：支持只检查系统、架构和下载源，不安装、不写配置。
- 安全默认值：真实 API Key、本地下载源、安装包和日志默认不会提交到仓库。
- CI 兜底：GitHub Actions 覆盖 PowerShell 语法、Windows 兼容计划和 macOS 安装计划。

## 快速开始

从 [Releases](https://github.com/seaworld008/codex-one-click-installer/releases/latest) 下载最新压缩包，解压后按系统双击入口：

| 系统 | 推荐入口 | 命令行入口 |
| --- | --- | --- |
| Windows | `Windows双击安装Codex.cmd` | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-codex.ps1` |
| macOS | `macOS双击安装Codex.command` | `chmod +x macOS双击安装Codex.command install-codex-macos.sh && ./macOS双击安装Codex.command` |

安装完成后，重新打开终端或 PowerShell：

```bash
codex --version
codex
```

## 支持范围

- Windows 10 / Windows 11：默认安装兼容优先的官方依赖，适配专业版、企业版、LTSC 常见环境。
- Windows 8.1：使用旧版官方 Git / Node.js / Python 兼容路径，尽量完成安装。
- Windows 8：使用更保守的旧版官方依赖，尽量完成安装。
- macOS 13.5+：支持 x64 和 Apple Silicon。

> Windows 8 / 8.1 已过官方生命周期。脚本会尽力安装，但 Codex 最新版本可能不再保证在旧系统完整可用。
> GitHub 官方托管 runner 不是 Windows 10 桌面版。仓库内的 GitHub Actions 会做安装计划、下载源和脚本语法矩阵测试；如需真实 Win10 专业版/企业版测试，请注册 self-hosted runner 并使用 workflow_dispatch 触发。

## 默认下载源

脚本默认使用国内友好的公开加速源：

- Node.js / Python / Git for Windows：优先 `https://npmmirror.com/mirrors/...`，失败后回退官方源。
- npm registry：默认 `https://registry.npmmirror.com`，安装 Codex CLI 失败时自动回退 `https://registry.npmjs.org`。

如果你在海外网络、公司内网或有自己的镜像，可设置 `CODEX_DOWNLOAD_MIRROR=official`，或使用环境变量 / `downloads.local.json` 覆盖具体 URL。

## Windows

解压最新 Release 后双击运行：

```text
Windows双击安装Codex.cmd
```

或在 PowerShell 中运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-codex.ps1
```

可选参数：

```powershell
.\install-codex.ps1 -SkipGit -SkipPython -SkipSkills -SkipCodexApp
```

预检模式，不安装、不写配置，适合先排查系统兼容性和下载源：

```powershell
.\install-codex.ps1 -CheckOnly -VerifyDownloads -NoPause
```

## macOS

解压最新 Release 后双击运行：

```text
macOS双击安装Codex.command
```

如果系统提示没有执行权限，再用终端运行：

```bash
chmod +x macOS双击安装Codex.command install-codex-macos.sh
./macOS双击安装Codex.command
```

> 说明：Windows 和 macOS 的双击入口格式不同，所以仓库提供 `.cmd` 和 `.command` 两个原生入口。它们会自动调用对应系统的安装脚本。

## 密钥配置

脚本会在安装过程中提示输入 `OPENAI_API_KEY`。也可以在脚本同目录创建 `codex-auth.json`：

```json
{"OPENAI_API_KEY":"YOUR_OPENAI_API_KEY"}
```

`codex-auth.json` 已加入 `.gitignore`，不要提交真实密钥。

## 私有下载源与域名去敏

仓库默认只保留公开官方下载源，不包含私有域名、签名 URL、临时 token 或镜像域名。

如果需要使用自己的下载源，请使用环境变量或本地 `downloads.local.json` 覆盖；该文件已加入 `.gitignore`。

可用字段 / 环境变量：

| 字段 | 环境变量 | 用途 |
| --- | --- | --- |
| `DownloadMirror` | `CODEX_DOWNLOAD_MIRROR` | 下载源模式：`china` 或 `official` |
| `NodeVersion` | `CODEX_NODE_VERSION` | 覆盖默认 Node.js 版本 |
| `PythonVersion` | `CODEX_PYTHON_VERSION` | 覆盖默认 Python 版本 |
| `GitUrl` | `CODEX_GIT_URL` | Git for Windows 安装包 |
| `NodeUrl` | `CODEX_NODE_URL` | Node.js 安装包 |
| `PythonUrl` | `CODEX_PYTHON_URL` | Python 安装包 |
| `SkillsUrl` | `CODEX_SKILLS_URL` | 可选 Skills zip 包 |
| `CodexAppUrl` | `CODEX_APP_INSTALLER_URL` | 可选 Codex App 安装器 |
| `NpmRegistry` | `CODEX_NPM_REGISTRY` | 可选 npm registry |
| `CodexBaseUrl` | `CODEX_BASE_URL` | 可选 OpenAI 兼容 API 地址 |
| `CodexModel` | `CODEX_MODEL` | 可选默认模型 |

示例：

```json
{
  "DownloadMirror": "china",
  "SkillsUrl": "https://example.invalid/codex-skills.zip",
  "CodexAppUrl": "https://example.invalid/Codex%20Installer.exe",
  "NpmRegistry": "https://registry.npmmirror.com",
  "CodexBaseUrl": "https://api.openai.com/v1",
  "CodexModel": "gpt-5.5"
}
```

## GitHub Actions 兼容性测试

仓库提供 `.github/workflows/compatibility.yml`：

- Windows PowerShell 5.1 语法解析。
- Windows 10 Pro、Windows 10 Enterprise LTSC、Windows 11、Windows 8/8.1 的安装计划模拟。
- Windows hosted runner 的真实环境预检。
- macOS x64 / arm64 安装计划模拟。
- 可选 self-hosted Win10 Pro / Enterprise 真实机器测试。

真实 Win10 桌面版测试需要在 GitHub 仓库注册 self-hosted runner，并给机器加标签：

```text
self-hosted, Windows, X64, win10-pro
self-hosted, Windows, X64, win10-enterprise
```

然后在 GitHub Actions 页面手动运行 `Compatibility` workflow，并把 `run_self_hosted_windows` 设为 `true`。

## 安全提示

- 不要提交 `codex-auth.json`、`downloads.local.json`、安装包、zip 包或日志文件。
- 脚本写入配置前会备份已有 `~/.codex/config.toml`。
- Windows 日志在 `%TEMP%\codex-installer`。
- macOS 日志在 `${TMPDIR}/codex-installer`。

## 参与贡献

欢迎提交 Issue、改进脚本、补充真实设备测试结果或提供新的下载源兼容反馈。为了让问题更快被复现，请尽量带上：

- 操作系统版本、CPU 架构和终端类型。
- 运行的入口文件或命令。
- 是否使用代理、公司内网或自定义镜像。
- 预检命令输出、错误截图或日志中的关键错误信息。

适合新贡献者的任务会标记为 `good first issue`，需要社区协助验证的任务会标记为 `help wanted`。
