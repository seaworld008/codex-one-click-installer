# 安全政策

## 支持版本

| 版本 | 安全更新 |
| --- | --- |
| 2.x | 支持 |
| 1.x | 不再支持，请升级到最新版 |

本仓库只维护包装脚本和发布流程。Codex CLI、ChatGPT 桌面应用、账号服务和官方安装器的漏洞应同时参考 OpenAI 的安全与支持渠道。

## 私密报告漏洞

请使用本仓库的 [GitHub Private Vulnerability Reporting](https://github.com/seaworld008/codex-one-click-installer/security/advisories/new)。

报告中请包含：

- 受影响版本、平台和架构。
- 最小复现步骤、预期行为和实际行为。
- 攻击者前提、影响范围和是否已公开。
- 可安全共享的日志、哈希或 PoC。

不要在 Issue、PR、截图或日志中提交：

- API Key、access token、cookie、认证文件。
- 带查询参数的签名 URL、代理密码、私有 CA 私钥。
- 公司内网域名、真实用户名、设备标识和其他个人信息。

如日志包含上述内容，请先替换为 `<redacted>`。如果密钥已经公开，先在对应系统中撤销或轮换，再继续报告。

## 响应预期

- 维护者会尽快确认收到报告并判断归属。
- 在修复、验证和发布安全版本前，请避免公开可直接利用的细节。
- 如果问题属于 OpenAI、Microsoft Store、npm、Homebrew 或操作系统上游，维护者会说明边界并协助提供最小上游复现。

## 信任边界

v2 默认信任：

- HTTPS 与操作系统证书存储。
- `chatgpt.com` 提供的官方 Codex bootstrap。
- bootstrap 获取的 `releases.openai.com` 版本元数据、SHA256 清单及其官方 GitHub Release 回退。
- Microsoft Store / OpenAI 官方 Store 签名 MSIX；回退包还必须匹配预期 `OpenAI.Codex` identity、Store publisher 和架构。
- 用户显式选择的系统包管理器。

v2 不信任并拒绝默认执行：

- 仓库内置或第三方 EXE、MSI、PKG、DMG。
- 没有摘要与签名来源链的镜像安装包。
- 任意 URL 下载的 Skills ZIP。
- 通过 Issue、PR 或配置文件传入的秘密值。

## Release 验证

正式 Release 提供 `SHA256SUMS` 和 SPDX SBOM。发布工作流要求 annotated tag 已进入 `main`，在发布前后核对远端 tag，从精确 ref 构建并解包复验执行权限，拒绝包含 EXE/MSI、密钥模板或本地配置的资产。资产先在 draft 中下载回读，确认四项文件及摘要一致后才公开，并生成 GitHub/Sigstore provenance 与 SBOM attestation；既有公开资产不允许不一致覆盖。

校验失败时不要继续运行安装器，请保留文件哈希和 Release URL并私密报告。
