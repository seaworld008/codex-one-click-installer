# 安装后的 Codex 配置参考

安装器只安装并验证 Codex CLI 和请求的桌面应用，不会创建、覆盖或合并你的配置与认证文件。这样重装或更新时不会破坏已有模型、权限、MCP、代理或企业策略。

## 配置文件位置

- 个人默认配置：`~/.codex/config.toml`
- 项目配置：仓库内的 `.codex/config.toml`
- Unix 系统配置：`/etc/codex/config.toml`

CLI、桌面应用和 IDE 扩展共享这些配置层。命令行参数优先级最高；项目配置只会在信任该项目后加载。

Windows PowerShell 打开个人配置：

```powershell
New-Item -ItemType Directory -Force "$HOME\.codex" | Out-Null
if (Test-Path "$HOME\.codex\config.toml") {
  Copy-Item "$HOME\.codex\config.toml" "$HOME\.codex\config.toml.bak"
}
notepad "$HOME\.codex\config.toml"
```

macOS / Linux 打开个人配置：

```bash
mkdir -p ~/.codex
if [ -f ~/.codex/config.toml ]; then
  cp ~/.codex/config.toml ~/.codex/config.toml.bak
fi
"${EDITOR:-vi}" ~/.codex/config.toml
```

## 日常使用的安全起点

```toml
model = "gpt-5.6"
model_reasoning_effort = "medium"
approval_policy = "on-request"
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
network_access = true
```

这份示例允许在当前工作区写文件并访问网络，工作区之外的敏感操作仍会按需请求批准。模型和可用功能可能因账号、工作区策略和客户端版本不同而变化；如果界面提供的模型不同，以当前 `/model` 列表和组织策略为准。

修改后可先验证配置语法和安装健康度：

```bash
codex --strict-config --version
codex doctor --summary
```

如果新配置导致启动失败，先恢复备份：

```bash
mv ~/.codex/config.toml.bak ~/.codex/config.toml
```

Windows PowerShell：

```powershell
Copy-Item "$HOME\.codex\config.toml.bak" "$HOME\.codex\config.toml" -Force
```

## 项目级覆盖

需要为单个仓库使用不同设置时，在仓库内创建 `.codex/config.toml`，不要复制个人认证文件：

```toml
model_reasoning_effort = "high"
approval_policy = "on-request"
sandbox_mode = "workspace-write"
```

仅在你信任该仓库及其配置时启用项目层。不要把 token、cookie、API Key、代理密码或 `auth.json` 提交到 Git。

## 网络较慢时

安装器默认使用 `auto`：先快速尝试 `releases.openai.com`，异常时自动切换到 `github.com/openai/codex` 的 OpenAI 官方 Release。强制指定方式：

```bash
./install-codex-linux.sh --network official
./install-codex-linux.sh --network github
```

Windows PowerShell：

```powershell
.\install-codex.ps1 -NetworkMode official
.\install-codex.ps1 -NetworkMode github
```

已有合规代理时，安装器会继承当前进程的 `HTTPS_PROXY`、`HTTP_PROXY` 和 `NO_PROXY`。企业 TLS 检查应使用组织下发的受信任根证书；不要关闭证书校验，也不要从不明镜像执行脚本。网络加速不会改变 OpenAI 的账号、地区、服务可用性或组织策略。

完整键名和优先级以 [OpenAI Config basics](https://learn.chatgpt.com/docs/config-file/config-basic) 与 [Configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference) 为准。
