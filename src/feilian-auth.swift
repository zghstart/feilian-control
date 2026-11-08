import Foundation
import LocalAuthentication
import Darwin

let socketPath = "/var/run/com.feiliancontrol.helper.sock"
let configPath = "/Library/PrivilegedHelperTools/feilian-control/auth.conf"
let args = CommandLine.arguments

guard args.count == 2, ["stop", "start", "ping"].contains(args[1]) else {
    FileHandle.standardError.write(Data("usage: feilian-auth stop|start|ping\n".utf8))
    exit(64)
}
let command = args[1]
let reason = command == "stop" ? "验证身份以停用飞连后台服务" : "验证身份以恢复飞连后台服务"
signal(SIGPIPE, SIG_IGN)

@Sendable
func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
    bytes.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return false }
        var offset = 0
        while offset < raw.count {
            let n = write(fd, base.advanced(by: offset), raw.count - offset)
            if n > 0 {
                offset += n
            } else if n < 0 && errno == EINTR {
                continue
            } else {
                return false
            }
        }
        return true
    }
}

func sendCommand(_ command: String) -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        FileHandle.standardError.write(Data("socket failed\n".utf8))
        return 1
    }
    defer { close(fd) }

    var timeout = timeval(tv_sec: command == "ping" ? 5 : 120, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathSize = MemoryLayout.size(ofValue: addr.sun_path)
    socketPath.withCString { path in
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            UnsafeMutableRawPointer(ptr).copyMemory(
                from: path,
                byteCount: min(strlen(path) + 1, pathSize)
            )
        }
    }

    let result = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else {
        let message = "cannot connect to feilian helper: \(String(cString: strerror(errno)))\n请运行 feilianctl doctor 检查安装和助手状态。\n"
        FileHandle.standardError.write(Data(message.utf8))
        return 1
    }

    let payload = Array((command + "\n").utf8)
    guard writeAll(fd, payload) else {
        let message = "failed to send helper command: \(String(cString: strerror(errno)))\n请运行 feilianctl doctor。\n"
        FileHandle.standardError.write(Data(message.utf8))
        return 1
    }

    var response = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    var readFailure: Int32 = 0
    while true {
        let n = buffer.withUnsafeMutableBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            return read(fd, base, raw.count)
        }
        if n > 0 {
            response.append(contentsOf: buffer[0..<n])
        } else if n < 0 && errno == EINTR {
            continue
        } else if n < 0 {
            readFailure = errno
            break
        } else {
            break
        }
    }

    let text = String(decoding: response, as: UTF8.self)
    print(text, terminator: "")
    if readFailure != 0 {
        let message = "failed to read helper response: \(String(cString: strerror(readFailure)))\n请运行 feilianctl doctor；若持续失败，请重新安装助手。\n"
        FileHandle.standardError.write(Data(message.utf8))
        return 1
    }
    if response.isEmpty {
        FileHandle.standardError.write(Data("helper returned an empty response\n请运行 feilianctl doctor。\n".utf8))
        return 1
    }
    return text.hasPrefix("status=0\n") ? 0 : 1
}

func readAuthMode() -> String? {
    guard let text = try? String(contentsOfFile: configPath, encoding: .utf8) else {
        return nil
    }
    for line in text.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("AUTH_MODE=") else { continue }
        let value = String(trimmed.dropFirst("AUTH_MODE=".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value == "none" || value == "touchid" ? value : nil
    }
    return nil
}

if command == "ping" {
    exit(sendCommand(command))
}

guard let authMode = readAuthMode() else {
    let message = "验证配置缺失、不可读或无效：\(configPath)\n本次操作已取消，不会静默跳过验证。请运行 feilianctl doctor。\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(2)
}

if authMode == "touchid" {
    let context = LAContext()
    var authError: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
        let message = "Touch ID unavailable: \(authError?.localizedDescription ?? "unknown")\n"
        FileHandle.standardError.write(Data(message.utf8))
        exit(2)
    }

    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
        if !success {
            let message = "Authentication failed: \(error?.localizedDescription ?? "cancelled")\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(1)
        }
        exit(sendCommand(command))
    }

    RunLoop.main.run()
} else {
    exit(sendCommand(command))
}
