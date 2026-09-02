Codex / ChatGPT 跨平台一键安装器 v2
=======================================

这是社区维护的便捷包装器，不是 OpenAI 官方安装器。
脚本调用 OpenAI 官方 Codex standalone 安装器，不重新打包 Codex，也不内置 EXE。

支持范围
--------

- Windows 11 x64 / Arm64：推荐
- Windows 10 1809+ x64：CLI 尽力兼容；桌面应用最低 build 19041
- macOS Intel / Apple Silicon
- Linux x64 / Arm64
- 不支持 Windows 8 / 8.1、32 位系统

快速安装
--------

Windows：

1. 双击 Windows双击安装Codex.cmd
2. 安装入口会安装 CLI，并尝试安装 ChatGPT 桌面应用；开发工具需显式选择。

macOS：

1. 双击 macOS双击安装Codex.command
2. Finder 首次阻止时请使用“右键 -> 打开”，不要递归清除 quarantine。

Linux：

  chmod +x install-codex-unix.sh install-codex-linux.sh
  ./install-codex-linux.sh

Linux 薄入口默认同时请求安装官方 ChatGPT 桌面应用。官方桌面预览支持
Ubuntu 24.04/26.04、Debian 13、Fedora 43/44 的 x64/Arm64；
不支持的发行版会保留已验证的 CLI 并报告部分成功。只安装 CLI：

  ./install-codex-linux.sh --skip-app

安装完成后：

  codex --version
  codex

第一次运行 codex 时，使用官方界面选择 ChatGPT 登录或其他可用认证方式。
本安装器不会询问 API Key，也不会创建或覆盖 auth.json / config.toml。
私有安装日志会记录安装器和子进程输出；不要把凭据放入参数，公开前仍须脱敏。

后续更新
--------

Windows：

  双击 Windows双击更新Codex.cmd

macOS：

  双击 macOS双击更新Codex.command

Linux：

  ./install-codex-linux.sh --update

Windows 命令行
--------------

只安装 CLI：

  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-codex.ps1

安装桌面应用：

  .\install-codex.ps1 -InstallDesktopApp

安装缺失开发工具：

  .\install-codex.ps1 -InstallDevTools

预检：

  .\install-codex.ps1 -CheckOnly -NonInteractive -NoPause

下载并检查官方 bootstrap，但不安装：

  .\install-codex.ps1 -CheckOnly -VerifyDownloads -NonInteractive -NoPause

Unix 命令行
-----------

通用参数：

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

示例：

  ./install-codex-macos.sh --install-app
  ./install-codex-linux.sh --release 0.149.1
  ./install-codex-unix.sh --check-only --verify-downloads --non-interactive

网络自动判断
------------

默认 auto 模式先短时探测 OpenAI CDN。无法快速取得有效 bootstrap 时，
自动切换到 github.com/openai/codex 的 OpenAI 官方 Release，并让官方
bootstrap 直接使用该通道，避免先等待不可用 CDN 的长超时。

  ./install-codex-linux.sh --network official
  ./install-codex-linux.sh --network github
  .\install-codex.ps1 -NetworkMode official
  .\install-codex.ps1 -NetworkMode github

流程只使用 OpenAI 官方 CDN、官方 GitHub Release 和官方桌面包，不关闭 TLS，
也不改变账号或服务的地区可用性。当前进程的 HTTPS_PROXY / HTTP_PROXY /
NO_PROXY 会被继承。

安装后配置
---------

安装完成会直接输出配置位置和修改步骤。个人配置位于：

  ~/.codex/config.toml

安全起点示例：

  model = "gpt-5.6"
  model_reasoning_effort = "medium"
  approval_policy = "on-request"
  sandbox_mode = "workspace-write"

修改后验证：

  codex --strict-config --version
  codex doctor --summary

完整可复制案例：docs/configuration.md

安全说明
--------

- 默认优先从 https://releases.openai.com/codex/install.sh 或 install.ps1 下载官方
  bootstrap；快速失败时只回退 OpenAI 官方 GitHub Release。
- bootstrap 先保存到本次运行专属临时目录，再执行；不使用 curl | sh / irm | iex。
- 官方 bootstrap 会验证版本化 Codex 包的 SHA256，并使用锁、staging 和原子切换。
- 不执行自定义 EXE，不安装任意远程 Skills ZIP。
- 不永久修改 npm registry / prefix 或 PowerShell ExecutionPolicy。
- 不关闭 Gatekeeper，不关闭 TLS 证书校验。
- 可用 CODEX_BOOTSTRAP_SHA256 固定 bootstrap 摘要。
- 不默认安装 Git、Node.js、Python 或 GitHub CLI。

企业 CA
-------

macOS / Linux 首次安装使用组织提供的 PEM bundle：

  export CURL_CA_BUNDLE=/absolute/path/company-ca-bundle.pem

Windows 由 IT 把组织根证书部署到系统受信任根证书存储。
CODEX_CA_CERTIFICATE 只影响安装后的 Codex 运行期网络，不能替代首次下载信任。
不要使用 curl -k 或关闭 PowerShell 证书校验。

Windows 桌面应用
---------------

官方 Store 产品 ID：

  9PLM9XGG6VKS

官方命令：

  winget install --id 9PLM9XGG6VKS --exact -s msstore

ChatGPT desktop app 最低要求 Windows build 19041。更旧的受支持 Windows 10
会继续验收 CLI，但把可选桌面步骤标记为部分成功并跳过下载。
winget 不可用时，脚本只会回退 OpenAI 官方 Store 签名 MSIX，不执行自定义 EXE。
回退路径会限制下载体积，并校验 OpenAI.Codex 包 identity、Store publisher、
目标架构、Authenticode 和 Add-AppxPackage 信任链。

Release 校验
------------

正式 Release 提供 ZIP、tar.gz、SHA256SUMS 和 SPDX SBOM，并为资产生成
GitHub/Sigstore provenance 与 SBOM attestation。

macOS：

  shasum -a 256 -c SHA256SUMS

Linux：

  sha256sum -c SHA256SUMS

压缩包会在 CI 中重新解包验证，.sh / .command 必须保持可执行权限。

可额外验证发布来源：

  gh attestation verify codex-one-click-installer-v2.0.1.zip --repo seaworld008/codex-one-click-installer

升级说明
--------

v1.x 通过 npm 安装的 Codex 可能与 standalone 同时存在。本安装器会验证本次
安装方法对应的确切文件和显式请求版本；PATH 仍优先旧版本时会失败。先检查：

  type -a codex
  codex --version
  codex doctor --summary

确认 standalone 工作正常后，如不再需要旧 npm 版本，再自行运行：

  npm uninstall -g @openai/codex

不要在验证新版本前卸载旧版本。安装器不会删除已有配置、认证或会话。

排错与反馈
----------

  codex --version
  codex doctor --summary

完整说明：

  https://github.com/seaworld008/codex-one-click-installer

官方 Codex CLI：

  https://learn.chatgpt.com/docs/codex/cli

公开反馈前请删除 API Key、token、签名 URL、私有域名、用户名和公司内部地址。
