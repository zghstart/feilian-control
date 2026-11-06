# 飞连 macOS 控制工具（FeiLian Control）

[![build](https://github.com/zghstart/feilian-control/actions/workflows/build.yml/badge.svg)](https://github.com/zghstart/feilian-control/actions/workflows/build.yml)

一键停用 / 恢复飞连（CorpLink）macOS 客户端：

- **仅退出界面**：VPN 断开，EDR / DLP / 杀毒等后台继续运行。
- **连后台一起停用**：停掉飞连的全部 launchd 任务和进程。
- **Touch ID**：日常停用 / 恢复只需要指纹，不需要每次输入管理员密码。
- **可恢复**：不卸载飞连，保留 App、配置和日志，随时可以恢复。

> **非官方项目**，与字节跳动 / 火山引擎 / 飞连官方无关。
>
> **请只在你有权管理的设备上使用。** 停用企业安全客户端可能违反公司 IT / BYOD 政策，并让设备在管理后台显示为离线或不合规。公司配发的设备请先获得授权。本项目不是绕过监管的工具。

GitHub 工程：<https://github.com/zghstart/feilian-control>

---

## 背景

飞连的“退出”通常只退出 `CorpLink` 界面，后台仍然保留零信任接入、EDR、DLP、终端管理等组件。它们由 launchd 拉起，普通 `kill` 之后还会自动恢复。

本项目用 launchd 的 `disable` / `bootout` 把这些组件停掉，并在需要时用 `enable` / `bootstrap` 恢复。停用范围包括：

| 类型 | 组件 |
| --- | --- |
| 界面 | `CorpLink` |
| Finder 扩展 | `com.volcengine.corplink.networkextension-wrapper.FinderSync` |
| 系统级守护进程 | `com.corplink.mdm.policy`（MDM 策略代理 `clpolicy`） |
| 系统级守护进程 | `com.volcengine.corplink.systemextension` |
| 系统级守护进程 | `com.volcengine.corplink.service` |
| 用户级 LaunchAgent | `com.volcengine.corplink.agent` |
| 用户级 LaunchAgent | `CorpLink` |
| 残留进程 | `CorpLinkExtension`、`corplink-service`、`CorplinkNe`、`clpolicy`、`CorpLink Finder Sync` |

### 停用 ≠ 卸载

停用后以下内容仍然保留：

- `/Applications/CorpLink.app`
- `/Library/CorpLink`
- `/usr/local/corplink`
- 用户配置、缓存、日志
- 各 launchd plist

因此“恢复飞连”可以正常工作。服务端已经收集的数据也不会因为本地停用而删除。

---

## 环境要求

- macOS，带 Touch ID（在 **macOS 26.6.2 / Darwin 25.6.0** 上测试）
- Xcode Command Line Tools：`xcode-select --install`
- 飞连 **3.2.16（3.2.16.12794）** 测试通过；其他版本如果 launchd label 或安装路径不同，需要调整脚本
- 安装 root 助手时需要**一次**管理员密码；之后日常操作只用 Touch ID

---

## 安装

```bash
git clone https://github.com/zghstart/feilian-control.git
cd feilian-control

make build          # 编译 Swift 助手
sudo make install   # 安装 root LaunchDaemon + CLI（一次性管理员密码）
make apps           # 生成三个 App 到 ~/Applications
```

安装后的文件：

| 路径 | 说明 |
| --- | --- |
| `/usr/local/libexec/feilian/feilian-daemon` | root 守护进程，监听 Unix socket |
| `/usr/local/libexec/feilian/feilian-auth` | 用户态 Touch ID 客户端 |
| `/usr/local/libexec/feilian/stop.sh` | 停用脚本（root 所有） |
| `/usr/local/libexec/feilian/start.sh` | 恢复脚本（root 所有） |
| `/usr/local/libexec/feilian/status.sh` | 状态检查 |
| `/usr/local/bin/feilianctl` | 用户命令入口 |
| `/Library/LaunchDaemons/com.feiliancontrol.helper.plist` | 开机自启的助手 |
| `/var/run/com.feiliancontrol.helper.sock` | 运行时 socket |
| `/var/log/feilian-control-helper.log` | 助手日志 |
| `~/Applications/退出飞连.app` | 停用入口 |
| `~/Applications/恢复飞连.app` | 恢复入口 |
| `~/Applications/飞连状态.app` | 状态入口 |

> 升级时安装脚本会先 `bootout` 同 label 的旧助手再重新加载；不会影响飞连本身。

---

## 使用

### 图形界面

| App | 用途 |
| --- | --- |
| `退出飞连.app` | 选择“仅退出界面”或“连后台一起停用”；后者会弹 Touch ID |
| `恢复飞连.app` | 恢复全部后台服务并打开飞连；会弹 Touch ID |
| `飞连状态.app` | 查看进程和 launchd 禁用状态；不需要验证 |

推荐的下班 / 上班流程：

1. **下班**：双击 `退出飞连.app` → **连后台一起停用** → Touch ID。
2. **上班**：双击 `恢复飞连.app` → **恢复** → Touch ID。
3. 需要确认时：双击 `飞连状态.app`。

### 命令行

```bash
feilianctl stop      # 停用，弹 Touch ID
feilianctl start     # 恢复，弹 Touch ID
feilianctl status    # 只读状态，不需要验证
```

也可以直接运行仓库里的脚本：

```bash
sudo ./scripts/stop.sh
sudo ./scripts/start.sh
./scripts/status.sh
```

### Touch ID 的行为

`feilian-auth` 使用 `LAContext.evaluatePolicy(.deviceOwnerAuthentication, ...)`：

- 默认弹 **Touch ID**。
- 如果指纹不可用或连续失败，macOS 可能提供**登录密码**作为兜底。
- 如果你希望严格只允许指纹，把 `src/feilian-auth.swift` 里的策略改成 `.deviceOwnerAuthenticationWithBiometrics`，重新 `make build && sudo make install`。

---

## 安全设计

```
App / feilianctl
      │
      ▼
feilian-auth（当前用户，负责 Touch ID）
      │  Unix socket: /var/run/com.feiliancontrol.helper.sock
      ▼
feilian-daemon（root，LaunchDaemon）
      │  固定命令 "stop" / "start"
      ▼
/usr/local/libexec/feilian/stop.sh 或 start.sh（root 所有）
```

`feilian-daemon` 的限制：

1. **只接受** `stop` 和 `start` 两个命令，不接受任意命令或路径。
2. 校验连接的对端 UID 必须是当前 `/dev/console` 的登录用户（或 root）。
3. 校验对端可执行文件必须是已安装的 `/usr/local/libexec/feilian/feilian-auth`。
4. 执行的脚本固定在 `/usr/local/libexec/feilian/`，root 所有，普通用户不可写。

这不是沙箱：如果你账户下的恶意程序能够运行代码，它仍然可以运行 `feilian-auth`（会弹 Touch ID）或尝试注入。Touch ID 在这里是**操作确认**，不是对抗本机恶意软件的强安全边界。

---

## 卸载

只卸载 Touch ID 助手（飞连本身保留）：

```bash
sudo make uninstall
rm -rf ~/Applications/退出飞连.app \
       ~/Applications/恢复飞连.app \
       ~/Applications/飞连状态.app
```

如果要卸载飞连本身，请使用公司的官方卸载流程；本项目不删除飞连的文件和配置。

---

## 排错

**`cannot connect to feilian helper`**

助手没安装或没运行：

```bash
launchctl print system/com.feiliancontrol.helper
sudo tail -n 50 /var/log/feilian-control-helper.log
sudo make install
```

**Touch ID 不弹 / 验证失败**

- 检查“系统设置 → Touch ID 与密码”。
- 验证取消时会返回 `Authentication failed: ...`，重试即可。
- 指纹不可用时可能回退到登录密码，这是 `deviceOwnerAuthentication` 的行为。

**停用后还有残留进程**

```bash
sudo /usr/local/libexec/feilian/stop.sh
ps -axo pid,user,command | grep -iE 'CorpLink|corplink|clpolicy' | grep -v grep
```

**飞连升级后停不干净**

飞连升级可能改 label 或路径。检查：

```bash
ls /Library/LaunchDaemons /Library/LaunchAgents | grep -i corplink
launchctl print-disabled system | grep -i corplink
```

然后同步修改 `scripts/stop.sh` 和 `scripts/start.sh`。

**设备在管理后台显示离线 / 不合规**

这是停用后的预期行为。恢复飞连并重新登录后，状态通常会恢复。

---

## 开发

```bash
make check    # shell 语法、plist、Swift 类型检查
make build    # 编译 build/feilian-daemon 和 build/feilian-auth
make apps     # 重新生成三个 App
```

目录结构：

```
src/            Swift 助手和 Touch ID 客户端
scripts/        stop / start / status / feilianctl / 安装卸载
applescript/    三个 App 的源码
launchd/        LaunchDaemon plist
```

CI 在 macOS runner 上执行 `make check && make build`。欢迎提交 issue / PR，尤其是其他飞连版本的 label 和路径适配。

---

## English

A small macOS tool to stop and restore the FeiLian (CorpLink) endpoint security client. It ships three AppleScript apps and a CLI. Stopping can be UI-only, or include all background services (MDM policy agent, system extension, service, user agents, Finder Sync). A root LaunchDaemon gated by Touch ID runs fixed, root-owned stop/start scripts; it does not accept arbitrary commands.

It is a **stop**, not an uninstall: the CorpLink app, configuration, logs and launchd plists remain, so restore works.

Use only on devices you own and are authorized to manage. Stopping an enterprise security agent may violate your organization's policy and mark the device offline or non-compliant.

```bash
make build
sudo make install
make apps
```

Then use `退出飞连.app` / `恢复飞连.app`, or `feilianctl stop|start|status`.

---

## License

MIT
