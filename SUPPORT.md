# 支持边界

## 可以在本仓库反馈

- 安装脚本语法、参数、计划和退出码问题。
- 官方 bootstrap 下载、调用和本地验证流程问题。
- Windows Store ID、官方 MSIX 回退、macOS/Linux 入口问题。
- Release 压缩包权限、文件清单、SHA256 或 SBOM 问题。
- README 与实际脚本不一致。

## 应向上游反馈

- Codex CLI 自身崩溃、模型行为、账号额度或服务可用性。
- ChatGPT 桌面应用功能、自动更新或 Microsoft Store 服务问题。
- npm、Homebrew、winget、系统包管理器或操作系统本身的问题。

## 提交 Issue 前

```bash
codex --version
codex doctor --summary
```

Windows：

```powershell
.\install-codex.ps1 -CheckOnly -NonInteractive -NoPause
```

macOS / Linux：

```bash
./install-codex-unix.sh --check-only --non-interactive
```

请提供 Release/tag、安装或更新模式、平台、架构、关键报错和经过脱敏的诊断结果。不要粘贴 API Key、token、签名 URL、私有域名或完整认证文件。
