Codex 跨平台一键安装与更新包
============================

适用系统：
- Windows 10 / Windows 11：默认使用兼容优先依赖，适配专业版、企业版、LTSC 常见环境
- Windows 8 / Windows 8.1：尽量使用仍可获取的旧版官方依赖；如果官方依赖不支持，会尽早提示
- macOS 13.5+：x64 / Apple Silicon

默认安装内容：
- Windows / macOS：安装和更新 Codex CLI
- Windows：未禁用 App 步骤时，默认按官方 Microsoft Store / winget 路径尽量安装或更新 Codex Windows App；如果 winget 失败或 300 秒内未完成，会改用同目录 Codex Installer.exe 兜底
- Windows / macOS：如果同目录存在 codex-skills.zip，或配置了 CODEX_SKILLS_URL，会安装或更新 Codex Skills
- Git / Node.js / Python：默认每次运行都做补缺检查；显式开启依赖更新时才升级

推荐使用方式：
1. 解压本压缩包到任意目录，例如桌面。
2. Windows 用户双击「Windows双击安装Codex.cmd」。
3. macOS 用户双击「macOS双击安装Codex.command」。
4. Windows 出现 UAC 管理员授权时点击“是”；macOS 如需管理员权限会提示输入系统密码。
5. 脚本会自动补齐 Git、Node.js、Python，并安装 Codex CLI；Windows 会优先通过 Microsoft Store / winget 处理 Codex App，慢或失败时改用本包内置的 Codex Installer.exe，已配置 Skills 包时也会同步常用 Skills。
6. 如果本机已安装且 codex --version 可用，安装模式会默认跳过 Codex CLI 重装，但仍会补齐 Git、Node.js、Python；需要重装时按提示确认，或使用 -Force。
7. 首次安装且未检测到 auth.json 时，可在输入 OPENAI_API_KEY 的步骤粘贴自己的 Key，然后回车。
8. 安装完成后，重新打开 PowerShell 或终端，执行：
   codex --version
   codex

后续更新：
- Windows 用户双击「Windows双击更新Codex.cmd」。
- macOS 用户双击「macOS双击更新Codex.command」。
- Windows 命令行更新：
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-codex.ps1 -Update
- macOS 终端更新：
  ./install-codex-macos.sh --update
- 如需连 Git / Node.js / Python 也按当前计划版本更新：
  Windows: .\install-codex.ps1 -Update -UpdateDependencies
  macOS: ./install-codex-macos.sh --update --update-dependencies
- 如需强制重装 Codex CLI 以及已配置的可选 App/Skills：
  Windows: .\install-codex.ps1 -Force
- 如需备份后重新生成 Codex 配置/认证文件：
  Windows: .\install-codex.ps1 -Reconfigure
  macOS: ./install-codex-macos.sh --reconfigure
- 如需完全不写 Codex 配置/认证文件：
  Windows: .\install-codex.ps1 -SkipConfig
  macOS: ./install-codex-macos.sh --skip-config

说明：
- Windows 和 macOS 的双击入口格式不同，所以压缩包里会同时放 .cmd 和 .command 两个入口。
- 如果 macOS 提示没有执行权限，可以打开终端进入本目录后执行：
  chmod +x macOS双击安装Codex.command macOS双击更新Codex.command install-codex-macos.sh
  ./macOS双击安装Codex.command

可选免输入密钥方式：
- 在本目录创建 codex-auth.json，内容格式如下：
  {"OPENAI_API_KEY":"YOUR_OPENAI_API_KEY"}
- 如果 %USERPROFILE%\.codex\auth.json 或 ~/.codex/auth.json 不存在，脚本会复制 codex-auth.json。
- 如果已有 auth.json，脚本默认保留，不会覆盖；需要覆盖时 Windows 请显式传入 -Reconfigure，macOS 请显式传入 --reconfigure。

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

Codex Windows App 可选安装：
- 默认方式：脚本会尝试 winget install Codex -s msstore；如果已检测到 App，会尝试 winget upgrade Codex -s msstore。
- 官方说明：https://developers.openai.com/codex/app/windows
- 国内/离线兜底：如果 winget 不可用、失败或 300 秒内未完成，脚本会自动改用同目录 Codex Installer.exe。
- 企业自定义兜底：如需使用自己的可信安装器下载源，可设置 CODEX_APP_INSTALLER_URL / downloads.local.json 的 CodexAppUrl。
- 内置 Codex Installer.exe 不是首选更新源；如关注最新 App 版本，优先使用 winget 或替换为刚从官方入口下载的新安装器。
- App 是可选步骤；Store / winget / 自定义安装器失败时，不影响 Codex CLI、Git、Node.js、Python 或 Skills 的安装结果。
- 如只想安装 CLI，可运行 install-codex.ps1 时添加 -SkipCodexApp。

更新策略：
- Codex CLI：更新到 npm registry 可获取的 @openai/codex@latest。
- Codex Windows App：默认通过 Microsoft Store / winget 尝试安装或更新；失败或超时后使用同目录 Codex Installer.exe，再尝试自定义下载源。
- Codex Skills：提供 codex-skills.zip 或 CODEX_SKILLS_URL 时才重新同步。
- 配置与认证：默认保留已有 config.toml / auth.json；仅缺失时补写，或在显式传入 -Reconfigure / --reconfigure 时备份后重写。
- Windows 如果配置写入后后续步骤失败，会自动还原本次修改过的 config.toml / auth.json；成功时备份保留在 %USERPROFILE%\.codex\backups\installer-...。

Codex macOS App：
- OpenAI 官方 Codex App 文档提供 macOS Apple Silicon / Intel 下载入口。
- 本包当前只自动安装和更新 macOS Codex CLI，不自动下载、缓存或安装 macOS App 包。

预检排错：
- Windows 可在 PowerShell 中运行：
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-codex.ps1 -CheckOnly -VerifyDownloads -NoPause
- Windows 更新预检：
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-codex.ps1 -Update -CheckOnly -VerifyDownloads -NoPause
- 预检模式不会安装，也不会写入 Codex 配置；它会提前检查系统、架构、下载源、企业版/LTSC 风险和常见代理问题。
- GitHub Actions 已提供 Compatibility workflow，覆盖安装计划和更新计划。GitHub 托管 runner 不是真实 Win10 桌面版；如需真实 Win10 专业版/企业版测试，请注册 self-hosted runner 并使用 win10-pro / win10-enterprise 标签。

重要说明：
- 不建议把真实 API Key 硬编码到 install-codex.ps1 中。
- 不要把 codex-auth.json、downloads.local.json、安装包、zip 包提交到 GitHub。
- Windows 下载文件缓存目录：%TEMP%\codex-installer
- Windows 安装日志也在：%TEMP%\codex-installer
- Codex 配置文件写入：%USERPROFILE%\.codex\config.toml
- Codex 配置备份目录：%USERPROFILE%\.codex\backups
- Skills 安装到：%USERPROFILE%\.agents\skills
