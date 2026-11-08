# 安全说明

## 支持范围

通常只维护最新发布版本。请先使用最新 Release 复现问题，并附上 `feilianctl version` 与 `feilianctl doctor` 的输出；提交前移除用户名、主机名、企业地址等敏感信息。

## 报告漏洞

不要先在公开 issue 中披露可利用的权限漏洞。请使用 GitHub 的私密安全报告入口：

<https://github.com/zghstart/feilian-control/security/advisories/new>

请包含影响版本、触发条件、影响范围和最小复现步骤。不要发送真实密码、Touch ID 数据、企业内部配置或未经授权获取的数据。

## 安全边界

- root 助手只接受固定的 `stop` / `start` 和只读 `ping`，校验当前控制台用户和客户端可执行文件路径。
- 特权二进制、脚本和验证配置位于 `/Library/PrivilegedHelperTools/feilian-control`，不依赖可写的 `/usr/local` 子目录。
- 一键模式允许同一登录用户触发这两个固定动作，不等于通用 root 权限，也不是抵御本机恶意软件的沙箱。
- 需要操作确认时使用 `AUTH_MODE=touchid`。配置缺失或不可读时，操作应取消，而不是静默跳过验证。
- `doctor` 会检查关键文件是否由 root 所有、是否被符号链接替换，以及其他用户是否可写。
- 本项目不应用来绕过所在组织的设备管理或安全政策。
