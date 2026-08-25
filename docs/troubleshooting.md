# 故障排查

## 先确认版本和命令来源

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

如果存在多个 `codex`，PATH 中排在最前面的版本会生效。先确认 standalone 正常，再用原包管理器移除不需要的旧版本。

安装器会验证本次方法对应的确切目标和显式请求版本。如果它报告 PATH 冲突，先重新打开终端，再检查 `type -a codex` / `Get-Command codex -All`；不要删除尚未确认来源的文件。

## 只做预检

Windows：

```powershell
.\install-codex.ps1 -CheckOnly -NonInteractive -NoPause
```

macOS / Linux：

```bash
./install-codex-unix.sh --check-only --non-interactive
```

预检只验证系统、架构、参数和计划，不代表真实下载、安装、Store、代理或登录已经成功。

## 验证官方 bootstrap

Windows：

```powershell
.\install-codex.ps1 -CheckOnly -VerifyDownloads -NonInteractive -NoPause
```

macOS / Linux：

```bash
./install-codex-unix.sh --check-only --verify-downloads --non-interactive
```

这会下载并检查 bootstrap，但不会安装 Codex。bootstrap 仍会随上游更新；企业可以用 `CODEX_BOOTSTRAP_SHA256` 固定批准的摘要。

下载只发生在有体积上限的随机私有临时目录中；`CheckOnly + VerifyDownloads` 结束时会删除下载、工作目录和临时日志。

## 代理和企业 CA

检查代理变量是否被当前终端继承：

```bash
env | grep -Ei '^(https?_proxy|no_proxy|codex_ca_certificate|ssl_cert_file)='
```

不要把包含密码或签名参数的完整值贴到 Issue。使用 `<redacted>` 替换敏感部分。

macOS / Linux 首次下载安装使用组织提供的 PEM CA bundle：

```bash
export CURL_CA_BUNDLE=/absolute/path/company-ca-bundle.pem
./install-codex-unix.sh --check-only --verify-downloads --non-interactive
```

本仓库的 `curl` 和随后官方 bootstrap 使用的 `curl` 都会继承该变量。Windows 不读取 PEM 环境变量；应由 IT 通过组策略、MDM 或证书管理工具把组织根证书部署到 Windows 受信任根证书存储。

`CODEX_CA_CERTIFICATE` 是安装完成后 Codex CLI 运行期的网络配置，不能替代首次 bootstrap 下载的 curl/Windows 系统信任。不要使用 `curl -k`、`NODE_TLS_REJECT_UNAUTHORIZED=0` 或关闭 PowerShell 证书校验。

## Windows Store / winget

```powershell
winget search --id 9PLM9XGG6VKS --exact -s msstore
winget list --id 9PLM9XGG6VKS --exact -s msstore
```

ChatGPT desktop app 最低要求 Windows build 19041。CLI 在 build 17763+ 仍可尽力运行；更旧的受支持 Windows 10 会跳过可选桌面下载并报告部分成功，使用 `-RequireDesktopApp` 时则在预检阶段失败。

企业策略可能禁用 Microsoft Store。脚本可回退官方 Store 签名 MSIX；如果组织还禁止 AppX sideload，需要由 IT 使用 Intune/MDM 部署。桌面应用失败不会删除已验证的 CLI。

回退 MSIX 会先限制下载为 1 GiB 以内，校验包清单的 `OpenAI.Codex` identity、OpenAI Store publisher 与架构，再要求 Authenticode 和 `Add-AppxPackage` 验证通过。任何一步不一致都会停止。

## macOS Gatekeeper

Release 脚本不会自动清除 quarantine。Finder 拦截时：

1. 确认资产来自本仓库正式 Release 并验证 `SHA256SUMS`。
2. 使用“右键 → 打开”查看系统提示。
3. 在“系统设置 → 隐私与安全性”中核对被阻止的文件。

不要对解压目录运行 `xattr -dr com.apple.quarantine`。

## npm / Homebrew 兼容路径

只有显式选择时才使用：

```bash
./install-codex-unix.sh --method brew
./install-codex-unix.sh --method npm
```

`brew` 或 `npm` 不存在时，脚本会失败并给出提示，不会自动安装包管理器。npm registry 只作用于当前命令，不会写入 `~/.npmrc`。

## 提交脱敏诊断

Issue 中建议包含：

- 仓库 Release/tag。
- 操作系统完整版本、架构。
- 安装/更新入口与参数。
- `CheckOnly` 结果。
- `codex --version` 和经过脱敏的 doctor 摘要。
- 期望行为、实际行为、最小复现步骤。

不得包含 API Key、token、cookie、认证文件、签名 URL、代理密码、私有域名、用户名或公司内部路径。
