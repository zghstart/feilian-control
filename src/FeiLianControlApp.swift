import SwiftUI
import AppKit
import Combine

@main
struct FeiLianControlApp: App {
    @StateObject private var model = ControlModel()

    var body: some Scene {
        MenuBarExtra {
            Text(model.statusText)
            Divider()
            Button("停用飞连（全部后台）") { model.run("stop") }
            Button("仅退出飞连界面") { model.quitUI() }
            Button("恢复飞连") { model.run("start") }
            Divider()
            Button("查看详细状态…") { model.showStatus() }
            Button("验证方式：\(model.authModeText)") { model.showAuthInfo() }
            Divider()
            Button("退出菜单栏") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: model.isRunning ? "shield.fill" : "shield.slash")
        }
        .menuBarExtraStyle(.menu)
    }
}

final class ControlModel: ObservableObject {
    @Published var isRunning = false
    @Published var statusText = "飞连：检查中…"
    @Published var authModeText = "…"

    private var timer: Timer?
    private var refreshing = false

    init() {
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
        guard !refreshing else { return }
        refreshing = true
        DispatchQueue.global(qos: .utility).async {
            let running = Self.feilianRunning()
            let auth = Self.readAuthMode()
            DispatchQueue.main.async {
                self.isRunning = running
                self.statusText = running ? "飞连：运行中" : "飞连：已停用"
                self.authModeText = auth == "touchid" ? "Touch ID" : "一键（不验证）"
                self.refreshing = false
            }
        }
    }

    func run(_ command: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.runCommand("/usr/local/bin/feilianctl", [command])
            DispatchQueue.main.async {
                if result.status != 0 {
                    self.showAlert(
                        title: "操作失败",
                        message: result.output.isEmpty
                            ? "退出码 \(result.status)"
                            : result.output
                    )
                }
                self.refresh()
            }
        }
    }

    func quitUI() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Self.runCommand("/usr/local/bin/feilianctl", ["stop-ui"])
            DispatchQueue.main.async { self.refresh() }
        }
    }

    func showStatus() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.runCommand("/usr/local/bin/feilianctl", ["status"])
            DispatchQueue.main.async {
                self.showTextWindow(title: "飞连详细状态", message: result.output)
            }
        }
    }

    func showAuthInfo() {
        if authModeText == "Touch ID" {
            showAlert(
                title: "验证方式：Touch ID",
                message: """
                每次停用 / 恢复都会要求 Touch ID。

                切换到一键模式（不验证）：
                sudo sh -c 'echo AUTH_MODE=none > /usr/local/etc/feilian-control.conf'
                """
            )
        } else {
            showAlert(
                title: "验证方式：一键（不验证）",
                message: """
                停用 / 恢复不会弹 Touch ID。

                切换回 Touch ID：
                sudo sh -c 'echo AUTH_MODE=touchid > /usr/local/etc/feilian-control.conf'
                """
            )
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

    private static func feilianRunning() -> Bool {
        let checks: [[String]] = [
            ["-x", "CorpLink"],
            ["-x", "CorpLinkExtension"],
            ["-x", "corplink-service"],
            ["-x", "CorplinkNe"],
            ["-x", "CorpLink Finder Sync"],
            ["-f", "/corplink-mdm/policy/bin/ruby"],
        ]
        return checks.contains { runCommand("/usr/bin/pgrep", $0).status == 0 }
    }

    private static func readAuthMode() -> String {
        guard let text = try? String(
            contentsOfFile: "/usr/local/etc/feilian-control.conf",
            encoding: .utf8
        ) else {
            return "none"
        }
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("AUTH_MODE=") else { continue }
            let value = String(trimmed.dropFirst("AUTH_MODE=".count))
                .trimmingCharacters(in: .whitespaces)
            return value == "none" ? "none" : "touchid"
        }
        return "touchid"
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
                String(data: data, encoding: .utf8) ?? ""
            )
        } catch {
            return (1, "\(path): \(error.localizedDescription)\n")
        }
    }
}
