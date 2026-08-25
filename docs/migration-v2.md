# 从 v1.x 迁移到 v2

v2 是一次有意的安全与分发架构升级。旧配置和认证不会被删除，但部分旧参数与默认行为不再存在。

## 迁移前

记录当前命令来源与版本：

```bash
type -a codex
codex --version
```

Windows PowerShell：

```powershell
Get-Command codex -All
codex --version
```

不要删除 `~/.codex`。其中可能包含配置、认证、会话、Skills 和本地状态，v2 安装器默认完全保留。

## 安装 v2

使用新 Release 中的系统入口，或直接执行默认 standalone 路径：

```bash
./install-codex-macos.sh
# 或
./install-codex-linux.sh
```

Windows：

```powershell
.\install-codex.ps1
```

官方 installer 发现 npm / Bun 管理的旧 Codex 时会说明多安装来源风险。非交互模式不会自动卸载旧版本。

## 验证新路径

```bash
type -a codex
codex --version
codex doctor --summary
```

Windows：

```powershell
Get-Command codex -All
codex --version
codex doctor --summary --no-color --ascii
```

`codex doctor` 可能因为终端、认证、网络或 sandbox 给出非零退出码；迁移的硬门禁是新路径的 `codex --version` 成功。对 doctor 的失败逐项判断，不要忽略。

v2 安装器会先验证本次安装方法推导出的确切可执行文件；指定非 `latest` 时还会比对版本。如果 PATH 仍优先旧的 npm/Homebrew/standalone 命令，安装器会失败并要求重新打开终端，不会拿旧版本冒充新安装成功。

## 可选清理旧 npm 安装

只有在确认 standalone 路径已经生效后，才执行：

```bash
npm uninstall -g @openai/codex
hash -r
type -a codex
codex --version
```

如果旧版本由 Homebrew 或 Bun 管理，请使用对应包管理器，不要手工删除未知路径。

## 已移除能力

- Windows 8 / 8.1 与 Node 16 兼容路径。
- 内置 `Codex Installer.exe` 和自定义 EXE 下载。
- 自动安装任意 Skills ZIP。
- 自动创建 `auth.json` / `config.toml`。
- 安装时输入 API Key。
- 默认安装 Git、Node.js、Python 或其他通用开发工具。
- `downloads.local.json` 与第三方镜像自动优先。

这些能力要么已由官方 standalone 替代，要么会扩大权限、供应链或密钥风险。

## 桌面应用

旧文档中的 “Codex App” 已统一为 ChatGPT desktop app：

- Windows 使用 Store ID `9PLM9XGG6VKS`。
- macOS 的 `--install-app` 调用 `codex app`。
- Linux 桌面应用按官方发行版指南安装。

## 配置迁移

v1 可能写入过时的 `disable_response_storage`、顶层 `network_access` 或自定义 model provider。v2 不会修改它们。建议先备份，再用当前 CLI 检查：

```bash
cp ~/.codex/config.toml ~/.codex/config.toml.pre-v2.bak
codex --strict-config doctor --summary
```

只根据 [当前官方配置文档](https://learn.chatgpt.com/docs/config-file/config-basic) 修正报告的字段，不要让安装器替你放宽 sandbox 或网络权限。
