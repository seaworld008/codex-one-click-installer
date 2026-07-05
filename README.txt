Codex 跨平台一键安装包
======================

适用系统：
- Windows 10 / Windows 11：默认使用兼容优先依赖，适配专业版、企业版、LTSC 常见环境
- Windows 8 / Windows 8.1：尽量使用仍可获取的旧版官方依赖；如果官方依赖不支持，会尽早提示
- macOS 13.5+：x64 / Apple Silicon

推荐使用方式：
1. 解压本压缩包到任意目录，例如桌面。
2. Windows 用户双击「Windows双击安装Codex.cmd」。
3. macOS 用户双击「macOS双击安装Codex.command」。
4. Windows 出现 UAC 管理员授权时点击“是”；macOS 如需管理员权限会提示输入系统密码。
5. 脚本会自动下载并安装：Git、Node.js、Python、Codex CLI；如已配置安装包，也会安装 Codex Windows App 和常用 Skills。
6. 到输入 OPENAI_API_KEY 的步骤时，粘贴自己的 Key，然后回车。
7. 安装完成后，重新打开 PowerShell 或终端，执行：
   codex --version
   codex

说明：
- Windows 和 macOS 的双击入口格式不同，所以压缩包里会同时放 .cmd 和 .command 两个入口。
- 如果 macOS 提示没有执行权限，可以打开终端进入本目录后执行：
  chmod +x macOS双击安装Codex.command install-codex-macos.sh
  ./macOS双击安装Codex.command

可选免输入密钥方式：
- 在本目录创建 codex-auth.json，内容格式如下：
  {"OPENAI_API_KEY":"YOUR_OPENAI_API_KEY"}
- 脚本检测到 codex-auth.json 后，会自动复制到 %USERPROFILE%\.codex\auth.json。

可选私有下载源：
- 默认优先使用国内友好的公开加速源：npmmirror 下载镜像和 registry.npmmirror.com。
- 如果加速源不可用，脚本会尽量回退官方源。
- 开源仓库中不会包含私有域名、签名 URL 或临时 token。
- 如果你需要使用自己的下载源，在本目录创建 downloads.local.json，或者设置环境变量：
  CODEX_DOWNLOAD_MIRROR
  CODEX_NODE_VERSION
  CODEX_PYTHON_VERSION
  CODEX_GIT_URL
  CODEX_NODE_URL
  CODEX_PYTHON_URL
  CODEX_SKILLS_URL
  CODEX_APP_INSTALLER_URL
  CODEX_NPM_REGISTRY
  CODEX_BASE_URL
  CODEX_MODEL

预检排错：
- Windows 可在 PowerShell 中运行：
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-codex.ps1 -CheckOnly -VerifyDownloads -NoPause
- 预检模式不会安装，也不会写入 Codex 配置；它会提前检查系统、架构、下载源、企业版/LTSC 风险和常见代理问题。
- GitHub Actions 已提供 Compatibility workflow。GitHub 托管 runner 不是真实 Win10 桌面版；如需真实 Win10 专业版/企业版测试，请注册 self-hosted runner 并使用 win10-pro / win10-enterprise 标签。

重要说明：
- 不建议把真实 API Key 硬编码到 install-codex.ps1 中。
- 不要把 codex-auth.json、downloads.local.json、安装包、zip 包提交到 GitHub。
- Windows 下载文件缓存目录：%TEMP%\codex-installer
- Windows 安装日志也在：%TEMP%\codex-installer
- Codex 配置文件写入：%USERPROFILE%\.codex\config.toml
- Skills 安装到：%USERPROFILE%\.agents\skills
