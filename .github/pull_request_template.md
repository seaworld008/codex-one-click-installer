## 变更摘要

<!-- 说明为什么要改，以及用户可见行为。不要粘贴任何真实密钥、令牌、私有域名或内网地址。 -->

## 影响范围

- 仓库版本（`VERSION`）：
- 安装模式：安装 / 更新 / `CheckOnly` / 发布
- 平台与版本：
- CPU 架构：x64 / arm64
- 下载源：official / 自定义（请去敏）

## 验证

- [ ] `python3 -m unittest discover -s tests -v`
- [ ] `bash -n install-codex-unix.sh install-codex-macos.sh install-codex-linux.sh macOS双击安装Codex.command macOS双击更新Codex.command scripts/package-release.sh`
- [ ] 相关平台的 `CheckOnly` 已通过，且没有真正安装或写入用户配置
- [ ] 若改动发布清单，`scripts/package-release.sh` 已成功构建并验证 `dist/`
- [ ] 文档、脚本和 `VERSION` 中的版本/平台支持范围一致

## 安全与回滚

- [ ] 日志和截图已移除 API Key、token、认证 JSON、用户名、私有地址和代理信息
- [ ] 未提交 `.exe`、`.msi`、密钥文件或构建产物
- [ ] 已说明失败后的回滚方式，或此变更不需要回滚

回滚说明：
