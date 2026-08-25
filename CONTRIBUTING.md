# 贡献指南

感谢改进 Codex 一键安装器。这个仓库会在用户机器上下载并执行安装流程，因此安全、可回滚和证据准确性优先于功能数量。

## 开发原则

- 默认使用 OpenAI、操作系统或可信包管理器的官方分发路径。
- 不提交二进制安装包、真实密钥、本地配置、日志或签名 URL。
- 不通过关闭证书校验、Gatekeeper、sandbox 或持久 ExecutionPolicy 解决兼容问题。
- 不把 `CheckOnly`、CI 语法通过或 HTTP 可达性表述为真实安装成功。
- 可选步骤失败必须明确呈现“部分成功”，不能吞掉错误后报告全部完成。
- 保留用户已有 Codex 配置、认证、Skills、会话和其他包管理器安装。

## 本地验证

macOS / Linux：

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
bash -n install-codex-unix.sh install-codex-macos.sh install-codex-linux.sh
bash -n macOS双击安装Codex.command macOS双击更新Codex.command

CODEX_TEST_UNAME_S=Darwin CODEX_TEST_ARCH=arm64 \
  ./install-codex-unix.sh --check-only --non-interactive
CODEX_TEST_UNAME_S=Linux CODEX_TEST_ARCH=x86_64 \
  ./install-codex-unix.sh --check-only --non-interactive

./scripts/package-release.sh
git diff --check
```

如果已安装 ShellCheck：

```bash
shellcheck install-codex-unix.sh install-codex-macos.sh install-codex-linux.sh
shellcheck macOS双击安装Codex.command macOS双击更新Codex.command
```

Windows PowerShell 5.1：

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path .\install-codex.ps1),
  [ref]$tokens,
  [ref]$errors
) | Out-Null
if ($errors.Count) { throw ($errors | Out-String) }

.\install-codex.ps1 -CheckOnly -NonInteractive -NoPause
```

## 下载与执行变更

新增任何下载路径时，PR 必须说明：

- 官方来源与维护主体。
- 版本和架构选择逻辑。
- SHA256、平台签名或包管理器验证方式。
- 超时、缓存、并发和失败回滚。
- 代理、企业 CA、离线与日志去敏边界。
- 错误摘要、HTML 错误页、同尺寸伪造文件和错误签名测试。

无法提供来源链和完整性验证的远程内容不能进入默认执行路径。

## 文档与兼容性

修改参数、默认行为、平台范围或 Release 资产时，同时更新：

- `README.md`
- `README.txt`
- `CHANGELOG.md`
- `docs/migration-v2.md` 或 `docs/troubleshooting.md`
- Issue Form 与仓库测试

所有“支持”声明都应标明证据层级：静态解析、计划模拟、真实安装、真实更新或发布后下载验证。

## Pull Request

- 一个 PR 聚焦一个可审查目标。
- 描述安全边界、用户可见变化、测试结果和未验证边界。
- 不提交 `dist/`；Release 资产由 tag 工作流生成。
- 合并前解决所有审查会话并等待必需检查通过。

## Release

版本由根目录 `VERSION` 唯一声明。正式 Release 使用 SemVer annotated tag，例如 `v2.0.0`。tag 必须精确指向已合并并通过检查的 `main` 提交，Release 工作流会拒绝 tag 与 `VERSION` 不一致。

发布工作流还会重新确认 tag commit 可从 `origin/main` 到达，并在上传前后核对远端 annotated tag 的 object/peeled commit。新资产先进入 draft，下载回读并验证 `SHA256SUMS` 后才公开；已存在 Release 只有在四项资产完全一致时才允许幂等重跑，禁止原地覆盖。ZIP/tar/SPDX 会生成 GitHub/Sigstore provenance 与 SBOM attestation。

仓库设置应同时保护 `main` 的 PR/required checks，并禁止已发布的 `v*` tag 更新或删除。流水线内校验不能替代 GitHub 侧的不可变引用策略。
