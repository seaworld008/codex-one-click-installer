# Changelog

本项目采用 [Semantic Versioning](https://semver.org/)。

## [Unreleased]

目标版本：`2.1.0`。

### Added

- 新增跨平台 `auto` 网络判断；OpenAI CDN 快速失败时自动切换 OpenAI 官方 GitHub Release，并避免后续重复等待不可用通道。
- Linux 官方桌面应用安装，覆盖 Ubuntu 24.04/26.04、Debian 13、Fedora 43/44 的 x64/Arm64 包。
- 安装结束输出配置修改步骤，并新增个人/项目配置、备份、验证和回滚案例。

### Changed

- Linux 薄入口默认同时请求安装 ChatGPT 桌面应用，可用 `--skip-app` 明确跳过。
- Upstream smoke 增加 Linux 官方文档与四个桌面包的有界探测。

## [2.0.1] - 2026-08-25

### Security

- Release 内容发现疑似秘密时仅输出固定的文件级诊断，不回显匹配值或秘密类别标签。
- 新增诊断脱敏回归测试，并启用 GitHub CodeQL 默认扫描覆盖 Actions 与 Python。

## [2.0.0] - 2026-08-25

### Added

- 新增 OpenAI 官方 standalone CLI 安装路径，支持固定 `--release` / `-Release`。
- 新增 Linux x64 / Arm64 入口及共享 Unix 核心脚本。
- 新增 Windows ChatGPT 桌面应用精确 Store ID 与官方 MSIX 回退。
- 新增可选开发工具安装、纯预检、bootstrap 下载验证和企业摘要固定。
- 新增定期 upstream smoke、确定性 Release 打包、SHA256SUMS 和 SPDX SBOM。
- 新增 GitHub/Sigstore provenance 与 SBOM attestation、draft 回读校验和幂等发布。
- 新增仓库行为测试、Security Policy、贡献指南、迁移指南和故障排查。

### Changed

- CLI 默认安装方式由 npm 改为 OpenAI 官方 standalone。
- 桌面产品名称统一为 ChatGPT desktop app。
- Windows/macOS 双击安装入口默认安装 CLI 并尝试桌面应用；开发工具改为显式选项。
- macOS 双击安装入口通过 `codex app` 使用官方桌面应用流程。
- Release 同时提供 ZIP 与 tar.gz，并验证解包后的执行权限。

### Security

- 下载 bootstrap 后先在随机私有临时目录中检查，再执行；不使用 pipe-to-shell。
- 下载在传输期限制最大体积；Windows MSIX 额外绑定 `OpenAI.Codex` identity、Store publisher 和目标架构。
- Windows 桌面应用在下载前强制 build 19041 门槛，避免在较旧 LTSC 上下载必然无法部署的大型 MSIX。
- Codex 包的版本解析、SHA256、锁、staging、自检与原子切换委托给官方 installer。
- 安装验收绑定本次方法的确切目标和显式请求版本，并拒绝 PATH 用旧版本冒充成功。
- Release 要求 annotated tag 已进入 `main`，发布前后复核远端 tag；资产在 draft 中回读通过后才公开，不覆盖不一致的既有资产。
- 删除全流程 UAC、持久 ExecutionPolicy 修改、全局 npm registry/prefix 修改和 TLS 1.0/1.1。
- 删除 API Key 提示、`auth.json` / `config.toml` 生成和任意远程 Skills ZIP。
- 删除 macOS 递归 quarantine 清除。
- 所有 GitHub Actions 使用完整提交 SHA 固定。

### Removed

- 删除无法完整追溯来源与许可的 `Codex Installer.exe`。
- 删除 `codex-auth.example.json` 和 `downloads.local.example.json`。
- 删除 Windows 8 / 8.1、Node 16 和手工维护的 Git/Node/Python 下载清单。
- 删除旧 `winget install Codex -s msstore` 模糊包名路径。

### Breaking

- 不再自动创建 Codex 配置或认证文件。
- 不再默认安装或更新 Skills。
- 自定义 EXE、MSI、PKG 与任意 URL 下载执行不再支持。
- Windows 最低基线提升到 10.0.17763，Windows 11 为推荐平台。

## [1.2.0] - 2026-07-06

- Windows 幂等安装、更新入口和可选 App 兜底。
- 该版本的发布 ZIP 曾丢失 macOS 文件执行权限；已在 v2 发布链路中加入真实归档回归测试。

[Unreleased]: https://github.com/seaworld008/codex-one-click-installer/compare/v2.0.1...HEAD
[2.0.1]: https://github.com/seaworld008/codex-one-click-installer/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/seaworld008/codex-one-click-installer/compare/v1.2.0...v2.0.0
[1.2.0]: https://github.com/seaworld008/codex-one-click-installer/releases/tag/v1.2.0
