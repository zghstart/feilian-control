# 参与贡献

感谢改进 FeiLian Control。本项目只应在你有权管理的设备上测试和使用。

## 开发环境

- macOS 13 或更高版本。
- Xcode Command Line Tools：`xcode-select --install`。
- 无第三方依赖，不需要 CocoaPods、SwiftPM 包或 npm。

## 常用命令

```bash
make check             # 语法、plist、Swift、CLI 与 launchd mock 测试
make build             # 构建 Apple Silicon（arm64）二进制和菜单栏 App
make pkg               # 构建 pkg，并立即验证 SHA-256 校验文件
make apps              # 安装 App 到 ~/Applications
make print-version     # 查看工程版本
```

`make check` 和 `make pkg` 不会安装助手，也不会执行飞连的停用或恢复。

## 修改约定

- Shell 使用 2 空格缩进，Swift 使用 4 空格；见 `.editorconfig`。
- root 脚本使用固定 PATH，不接受调用方传入命令或脚本路径。
- `stop` / `start` 必须保持幂等，并真实返回失败，不能用 `|| true` 隐藏关键错误。
- 共享 launchd / Finder 逻辑放在 `scripts/service-common.sh`，行为变化应更新 `tests/services.sh`。
- Shell 的 `AUTH_MODE` 解析统一使用 `scripts/auth-common.sh`；菜单状态复用 `status.sh --snapshot`，不要另写进程匹配规则。
- 不在自动测试中对真实飞连服务执行 `stop`、`start` 或 `stop-ui`。
- 面向用户的变化同步更新 README 和 CHANGELOG。

## 验证与提交

1. 运行 `make check && make pkg`。
2. 如涉及真实飞连适配，在获授权的测试机上验证停用和恢复，并在 PR 中说明飞连/macOS 版本。
3. 不提交 `build/`、个人配置、日志、账号信息或企业内部地址。
4. 一次 PR 聚焦一个主题；说明问题、修改和已执行的验证。

## 发布（维护者）

1. 同步更新 `Makefile`、`app/Info.plist`、`scripts/feilianctl` 中的版本；`make check` 会检查三者一致。
2. 更新 `CHANGELOG.md`，运行 `make check && make pkg`。
3. 创建与工程版本完全一致的 tag，例如版本 `0.3.0` 对应 `v0.3.0`。
4. 推送 tag 前运行 `make check-tag TAG=v0.3.0`。Release workflow 会再次检查，防止发布错版包。

安全漏洞请不要直接公开到 issue，报告方式见 [SECURITY.md](SECURITY.md)。
