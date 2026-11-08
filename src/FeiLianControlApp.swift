import SwiftUI
import AppKit
import Combine
import ServiceManagement
import Darwin

final class FeiLianControlAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CommandLine.arguments.contains("--unregister-login-item") else { return }
        if SMAppService.mainApp.status == .notRegistered {
            exit(0)
        }
        SMAppService.mainApp.unregister { error in
            if let error {
                FileHandle.standardError.write(Data("无法注销登录项：\(error.localizedDescription)\n".utf8))
                exit(1)
            }
            exit(0)
        }
    }
}

@main
struct FeiLianControlApp: App {
    @NSApplicationDelegateAdaptor private var delegate: FeiLianControlAppDelegate
    @StateObject private var model = ControlModel()

    var body: some Scene {
        MenuBarExtra {
            Text(model.statusText)
            Divider()
            Button("停用飞连（全部后台）") { model.run("stop") }
                .disabled(model.isBusy)
            Button("仅退出飞连界面") { model.run("stop-ui") }
                .disabled(model.isBusy)
            Button("恢复飞连") { model.run("start") }
                .disabled(model.isBusy)
            Divider()
            Button("查看详细状态…") { model.showStatus() }
            Button("故障诊断…") { model.showDoctor() }
            Toggle("登录时自动启动", isOn: Binding(
                get: { model.launchAtLogin },
                set: { _ in model.toggleLaunchAtLogin() }
            ))
            Button("验证方式：\(model.authModeText)") { model.showAuthInfo() }
            Divider()
            Button("关于飞连控制") { model.showAbout() }
            Button("退出菜单栏") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: model.statusIcon)
                .accessibilityLabel(Text(model.statusText))
        }
        .menuBarExtraStyle(.menu)
    }
}

enum ControlState {
    case checking
    case running
    case uiOnly
    case stopped
    case unavailable
    case operating(String)

    var text: String {
        switch self {
        case .checking:
            return "飞连：检查中…"
        case .running:
            return "飞连：后台运行中"
        case .uiOnly:
            return "飞连：仅界面运行"
        case .stopped:
            return "飞连：已停用"
        case .unavailable:
            return "控制助手不可用（请点“故障诊断”）"
        case .operating(let text):
            return text
        }
    }

    var icon: String {
        switch self {
        case .checking:
            return "shield"
        case .running:
            return "shield.fill"
        case .uiOnly:
            return "shield"
        case .stopped:
            return "shield.slash"
        case .unavailable:
            return "exclamationmark.triangle"
        case .operating:
            return "arrow.triangle.2.circlepath"
        }
    }

    var isBusy: Bool {
        if case .operating = self { return true }
        return false
    }
}

final class ControlModel: ObservableObject {
    @Published private(set) var state: ControlState = .checking
    @Published private(set) var authMode = "none"
    @Published private(set) var launchAtLogin = false

    var statusText: String { state.text }
    var statusIcon: String { state.icon }
    var isBusy: Bool { state.isBusy }
    var authModeText: String {
        switch authMode {
        case "touchid":
            return "Touch ID"
        case "invalid":
            return "配置无效"
        default:
            return "一键（不验证）"
        }
    }

    private struct Snapshot {
        let uiRunning: Bool
        let backgroundRunning: Bool
        let helperAvailable: Bool
        let authMode: String
    }

    private var timer: Timer?
    private var refreshing = false
    private var refreshAfterCurrent = false

    init() {
        guard !CommandLine.arguments.contains("--unregister-login-item") else { return }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        refresh()
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = 1
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        guard !isBusy else { return }
        guard !refreshing else {
            refreshAfterCurrent = true
            return
        }
        refreshing = true
        DispatchQueue.global(qos: .utility).async {
            let snapshot = Self.readSnapshot()
            DispatchQueue.main.async {
                self.refreshing = false
                self.authMode = snapshot.authMode
                self.launchAtLogin = SMAppService.mainApp.status == .enabled
                guard !self.isBusy else { return }

                if !snapshot.helperAvailable {
                    self.state = .unavailable
                } else if snapshot.backgroundRunning {
                    self.state = .running
                } else if snapshot.uiRunning {
                    self.state = .uiOnly
                } else {
                    self.state = .stopped
                }

                if self.refreshAfterCurrent {
                    self.refreshAfterCurrent = false
                    self.refresh()
                }
            }
        }
    }

    func run(_ command: String) {
        guard !isBusy else { return }
        let progressText: String
        switch command {
        case "stop":
            progressText = "正在停用飞连全部后台…"
        case "start":
            progressText = "正在恢复飞连…"
        default:
            progressText = "正在退出飞连界面…"
        }
        state = .operating(progressText)

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.runCommand("/usr/local/bin/feilianctl", [command])
            DispatchQueue.main.async {
                self.state = .checking
                self.refresh()

                guard result.status != 0 else { return }
                let output = result.output.isEmpty
                    ? "命令退出码：\(result.status)"
                    : result.output
                self.showTextWindow(
                    title: "操作失败",
                    message: output + "\n\n可点击菜单中的“故障诊断…”检查安装和助手连接。"
                )
            }
        }
    }

    func showStatus() {
        showCommandOutput(title: "飞连详细状态", command: "status")
    }

    func showDoctor() {
        showCommandOutput(title: "飞连控制诊断", command: "doctor")
    }

    func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval {
                showAlert(
                    title: "需要允许后台登录项",
                    message: "请在“系统设置 → 通用 → 登录项与扩展”中允许“飞连控制”。"
                )
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            showAlert(
                title: "无法更改登录时自动启动",
                message: error.localizedDescription
            )
        }
    }

    func showAuthInfo() {
        let targetMode: String
        let title: String
        let description: String

        if authMode == "touchid" {
            targetMode = "none"
            title = "验证方式：Touch ID"
            description = "每次停用 / 恢复都会要求 Touch ID。\n\n切换到一键模式（不验证）："
        } else {
            targetMode = "touchid"
            title = authMode == "invalid" ? "验证方式配置无效" : "验证方式：一键（不验证）"
            description = authMode == "invalid"
                ? "AUTH_MODE 仅支持 none 或 touchid。可重置为 Touch ID："
                : "停用 / 恢复不会弹 Touch ID。\n\n切换回 Touch ID："
        }
        let command = "sudo sh -c 'echo AUTH_MODE=\(targetMode) > /Library/PrivilegedHelperTools/feilian-control/auth.conf'"

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "\(description)\n\(command)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "复制切换命令")
        if alert.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }

    func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        showAlert(
            title: "飞连控制 \(version)",
            message: "非官方开源工具，用于停用和恢复飞连客户端。\n\n停用不会卸载飞连或删除其配置。"
        )
    }

    private func showCommandOutput(title: String, command: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.runCommand("/usr/local/bin/feilianctl", [command])
            DispatchQueue.main.async {
                let output = result.output.isEmpty
                    ? "命令未返回内容（退出码 \(result.status)）。"
                    : result.output
                self.showTextWindow(title: title, message: output)
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func showTextWindow(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.alertStyle = .informational

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 320))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = message
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        scroll.documentView = textView
        alert.accessoryView = scroll
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private static func readSnapshot() -> Snapshot {
        let result = runCommand(
            "/Library/PrivilegedHelperTools/feilian-control/status.sh",
            ["--snapshot"]
        )
        var fields: [String: String] = [:]
        for line in result.output.split(separator: "\n") {
            let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 {
                fields[pair[0]] = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard result.status == 0 else {
            return Snapshot(
                uiRunning: false,
                backgroundRunning: false,
                helperAvailable: false,
                authMode: "invalid"
            )
        }
        return Snapshot(
            uiRunning: fields["ui_running"] == "true",
            backgroundRunning: fields["background_running"] == "true",
            helperAvailable: fields["helper_available"] == "true",
            authMode: fields["auth_mode"] ?? "invalid"
        )
    }

    private static func runCommand(
        _ path: String,
        _ args: [String]
    ) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (
                process.terminationStatus,
                String(decoding: data, as: UTF8.self)
            )
        } catch {
            return (1, "\(path): \(error.localizedDescription)\n")
        }
    }
}
