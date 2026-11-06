# 飞连 macOS 控制工具（FeiLian Control）

[![build](https://github.com/zghstart/feilian-control/actions/workflows/build.yml/badge.svg)](https://github.com/zghstart/feilian-control/actions/workflows/build.yml)

一个菜单栏 App，停用 / 恢复飞连（CorpLink）macOS 客户端：

- **菜单栏一键操作**：停用全部后台、仅退出界面、恢复飞连。
- **默认不验证**：点一下立即执行，不再每次输密码或按 Touch ID；需要时也可以切回 Touch ID。
- **可恢复**：不卸载飞连，保留 App、配置和日志，随时可以恢复。
- **开箱即用**：GitHub Releases 提供预编译的 `.pkg`，不需要 Xcode、不需要自己编译。

> **非官方项目**，与字节跳动 / 火山引擎 / 飞连官方无关。
>
> **请只在你有权管理的设备上使用。** 停用企业安全客户端可能违反公司 IT / BYOD 政策，并让设备在管理后台显示为离线或不合规。公司配发的设备请先获得授权。本项目不是绕过监管的工具。

GitHub 工程：<https://github.com/zghstart/feilian-control>

---

## 下载安装（推荐）

到 [Releases](https://github.com/zghstart/feilian-control/releases/latest) 下载最新的 `FeiLianControl-*.pkg`。

1. 双击 `.pkg`，输入**一次**管理员密码。这是安装 root 助手的必要步骤，macOS 无法绕过。
2. 打开“飞连控制.app”，菜单栏会出现一个盾牌图标。
3. 点图标即可停用 / 恢复。

> **关于签名**：当前发布包没有使用 Apple Developer ID 签名和公证。如果 macOS 提示“无法打开，因为无法验证开发者”，请右键点击 `.pkg` → **打开**。仍然不行时，可以在终端运行：
>
> ```bash
> sudo installer -pkg ~/Downloads/FeiLianControl-0.2.0.pkg -target /
> ```
>
> 如果你有 Apple Developer 账号，可以自行用 Developer ID 重新签名并公证，获得真正的双击安装体验。

### 为什么只需要一次管理员密码？

要停用飞连的系统级 launchd 守护进程（零信任服务、EDR、DLP、MDM 策略代理等），必须有一个 root 权限的助手。安装这个助手需要一次管理员授权；之后日常的停用 / 恢复由助手执行，不再需要密码。

助手不是通用 root shell：

- 只接受 `stop` / `start` 两个固定命令。
- 只执行 `/usr/local/libexec/feilian/` 下 root 所有的固定脚本。
- 校验连接方的 UID 和可执行文件路径。

---

## 使用

### 菜单栏 App

打开“飞连控制.app”后，菜单栏出现盾牌图标：

| 菜单项 | 作用 |
| --- | --- |
| 停用飞连（全部后台） | 停掉界面、系统扩展、服务、用户 Agent、Finder 扩展和 MDM 策略代理 |
| 仅退出飞连界面 | 只退出 `CorpLink` 界面，后台安全组件继续运行 |
| 恢复飞连 | 重新启用并加载全部后台服务，然后打开飞连 |
| 查看详细状态… | 查看进程、launchd 状态和当前验证方式 |
| 验证方式：… | 查看 / 切换验证方式的说明 |
| 退出菜单栏 | 只退出这个菜单栏 App，不影响飞连 |

推荐流程：

1. **下班**：菜单栏图标 → **停用飞连（全部后台）**。
2. **上班**：菜单栏图标 → **恢复飞连**。

### 命令行

```bash
feilianctl stop      # 停用全部后台
feilianctl start     # 恢复全部后台
feilianctl stop-ui   # 只退出飞连界面
feilianctl status    # 查看详细状态（只读）
feilianctl auth      # 查看当前验证方式
```

### 验证方式：一键 / Touch ID

默认是**一键模式**，配置文件：

```text
/usr/local/etc/feilian-control.conf
```

内容：

```text
AUTH_MODE=none
```

一键模式不会弹 Touch ID，适合个人电脑的日常使用。

如果你希望每次停用 / 恢复都确认一次身份，改成 Touch ID：

```bash
sudo sh -c 'echo AUTH_MODE=touchid > /usr/local/etc/feilian-control.conf'
```

改回一键模式：

```bash
sudo sh -c 'echo AUTH_MODE=none > /usr/local/etc/feilian-control.conf'
```

Touch ID 模式使用 `LAContext.evaluatePolicy(.deviceOwnerAuthentication, ...)`：优先指纹；指纹不可用时，macOS 可能允许登录密码兜底。

> **安全权衡**：一键模式意味着任何以你的用户身份运行的程序，都可以调用 `/usr/local/bin/feilianctl stop|start`（或直接执行已安装的 `feilian-auth`）来触发这两个固定动作。它不能借此执行任意 root 命令，但可以停用 / 恢复飞连。对安全边界要求更高时，请使用 Touch ID 模式。

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

- macOS 13 或更高；在 **macOS 26.6.2 / Darwin 25.6.0** 上测试
- 预编译包同时支持 Apple Silicon 和 Intel
- 飞连 **3.2.16（3.2.16.12794）** 测试通过；其他版本如果 launchd label 或安装路径不同，需要调整脚本
- 源码构建需要 Xcode Command Line Tools：`xcode-select --install`

---

## 源码安装

```bash
git clone https://github.com/zghstart/feilian-control.git
cd feilian-control

make build          # 编译通用二进制（arm64 + x86_64）和菜单栏 App
sudo make install   # 安装 root 助手 + CLI（一次性管理员密码）
make apps           # 把“飞连控制.app”安装到 ~/Applications
```

安装后的文件：

| 路径 | 说明 |
| --- | --- |
| `/Applications/飞连控制.app` | pkg 安装的菜单栏 App |
| `~/Applications/飞连控制.app` | 源码安装的菜单栏 App |
| `/usr/local/libexec/feilian/feilian-daemon` | root 守护进程，监听 Unix socket |
| `/usr/local/libexec/feilian/feilian-auth` | 用户态客户端（一键 / Touch ID） |
| `/usr/local/libexec/feilian/stop.sh` | 停用脚本（root 所有） |
| `/usr/local/libexec/feilian/start.sh` | 恢复脚本（root 所有） |
| `/usr/local/libexec/feilian/status.sh` | 状态检查 |
| `/usr/local/bin/feilianctl` | 用户命令入口 |
| `/usr/local/etc/feilian-control.conf` | 验证方式配置 |
| `/Library/LaunchDaemons/com.feiliancontrol.helper.plist` | 开机自启的助手 |
| `/var/run/com.feiliancontrol.helper.sock` | 运行时 socket |
| `/var/log/feilian-control-helper.log` | 助手日志 |

> 升级时安装脚本会先 `bootout` 同 label 的旧助手再重新加载；不会影响飞连本身。

### 构建安装包

```bash
make pkg    # 生成 build/FeiLianControl-0.2.0.pkg 和 .sha256
```

生成的 pkg 未签名。发布到 GitHub Releases 后，用户首次打开可能需要右键 → 打开。

---

## 安全设计

```
菜单栏 App / feilianctl
      │
      ▼
feilian-auth（当前用户；一键模式直接执行，Touch ID 模式先验证）
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

一键模式不是沙箱：本机同一用户下的程序可以触发这两个固定动作，但不能借此执行任意 root 命令。Touch ID 模式提供的是**操作确认**，也不是对抗本机恶意软件的强安全边界。

---

## 卸载

```bash
sudo make uninstall
sudo pkgutil --forget com.feiliancontrol.pkg   # 如果通过 pkg 安装，清掉收据
```

`make uninstall` 会移除助手、配置和 `/Applications/飞连控制.app`。如果 App 在 `~/Applications`，请手动删除：

```bash
rm -rf ~/Applications/飞连控制.app
```

如果要卸载飞连本身，请使用公司的官方卸载流程；本项目不删除飞连的文件和配置。

---

## 排错

**macOS 提示 pkg 未签名 / 无法打开**

右键 `.pkg` → **打开**；或：

```bash
sudo installer -pkg ~/Downloads/FeiLianControl-0.2.0.pkg -target /
```

**`cannot connect to feilian helper`**

助手没安装或没运行：

```bash
launchctl print system/com.feiliancontrol.helper
sudo tail -n 50 /var/log/feilian-control-helper.log
```

重新安装 pkg，或源码安装时：

```bash
sudo make install
```

**Touch ID 不弹**

先确认配置：

```bash
feilianctl auth
cat /usr/local/etc/feilian-control.conf
```

`AUTH_MODE=none` 本来就不会弹；改成 `AUTH_MODE=touchid` 后再试。检查“系统设置 → Touch ID 与密码”。

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
make build    # 编译通用二进制和菜单栏 App
make pkg      # 生成未签名 .pkg
make apps     # 安装菜单栏 App 到 ~/Applications
```

目录结构：

```text
src/            Swift 助手、用户态客户端、菜单栏 App
scripts/        stop / start / status / feilianctl / 安装卸载
app/            菜单栏 App 的 Info.plist
pkg/            pkg 构建脚本和 component plist
applescript/    旧版三个 AppleScript App 的源码（可选）
launchd/        LaunchDaemon plist
```

旧版三个 App 仍可通过 `make legacy-apps` 生成；它们调用同一个 `feilianctl`，验证方式由配置文件决定。

CI 在 macOS runner 上执行 `make check && make build`。推送 `v*` tag 会触发 `.github/workflows/release.yml`，自动构建 pkg 并创建 GitHub Release。

欢迎提交 issue / PR，尤其是其他飞连版本的 label 和路径适配。

---

## English

A menu bar app to stop and restore the FeiLian (CorpLink) endpoint security client on macOS.

- One-click from the menu bar: stop all background services, quit the UI only, or restore.
- One-click mode by default (no Touch ID per action); Touch ID can be enabled in `/usr/local/etc/feilian-control.conf`.
- Download the prebuilt universal `.pkg` from GitHub Releases. One administrator password is required to install the root helper; it cannot be avoided on macOS.
- The package is not signed/notarized with an Apple Developer ID. If Gatekeeper blocks it, right-click → Open, or use `sudo installer -pkg ... -target /`.

The root helper only accepts fixed `stop` / `start` commands, verifies the peer UID and executable path, and runs fixed root-owned scripts. Stopping is not uninstalling: the CorpLink app, configuration, logs and launchd plists remain, so restore works.

Use only on devices you own and are authorized to manage. Stopping an enterprise security agent may violate your organization's policy and mark the device offline or non-compliant.

```bash
make build
sudo make install
make apps
```

Then use the menu bar app, or `feilianctl stop|start|stop-ui|status|auth`.

---

## License

MIT
