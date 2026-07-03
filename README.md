# Codex 跨平台一键安装器

这个仓库提供 Windows 和 macOS 的 Codex CLI 一键安装脚本。脚本会优先使用官方可获取的安装包；当系统或架构不满足官方安装条件时，会在下载和安装前尽早提示用户。

## 支持范围

- Windows 10 / Windows 11：安装当前官方依赖。
- Windows 8.1：使用旧版官方 Git / Node.js / Python 兼容路径，尽量完成安装。
- Windows 8：使用更保守的旧版官方依赖，尽量完成安装。
- macOS 13.5+：支持 x64 和 Apple Silicon。

> Windows 8 / 8.1 已过官方生命周期。脚本会尽力安装，但 Codex 最新版本可能不再保证在旧系统完整可用。

## Windows

双击运行：

```text
双击安装Codex.cmd
```

或在 PowerShell 中运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-codex.ps1
```

可选参数：

```powershell
.\install-codex.ps1 -SkipGit -SkipPython -SkipSkills -SkipCodexApp
```

## macOS

```bash
chmod +x install-codex-macos.sh
./install-codex-macos.sh
```

安装完成后，重新打开终端或 PowerShell：

```bash
codex --version
codex
```

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
  "SkillsUrl": "https://example.invalid/codex-skills.zip",
  "CodexAppUrl": "https://example.invalid/Codex%20Installer.exe",
  "NpmRegistry": "https://registry.npmjs.org",
  "CodexBaseUrl": "https://api.openai.com/v1",
  "CodexModel": "gpt-5.5"
}
```

## 安全提示

- 不要提交 `codex-auth.json`、`downloads.local.json`、安装包、zip 包或日志文件。
- 脚本写入配置前会备份已有 `~/.codex/config.toml`。
- Windows 日志在 `%TEMP%\codex-installer`。
- macOS 日志在 `${TMPDIR}/codex-installer`。
