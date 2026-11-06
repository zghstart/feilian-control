import Foundation
import LocalAuthentication
import Darwin

let socketPath = "/var/run/com.feiliancontrol.helper.sock"
let args = CommandLine.arguments

guard args.count == 2, args[1] == "stop" || args[1] == "start" else {
    FileHandle.standardError.write(Data("usage: feilian-auth stop|start\n".utf8))
    exit(64)
}
let command = args[1]
let reason = command == "stop" ? "验证身份以停用飞连后台服务" : "验证身份以恢复飞连后台服务"

func sendCommand(_ command: String) -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        FileHandle.standardError.write(Data("socket failed\n".utf8))
        return 1
    }
    defer { close(fd) }

    var timeout = timeval(tv_sec: 120, tv_usec: 0)
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
        let message = "cannot connect to feilian helper: \(String(cString: strerror(errno)))\n"
        FileHandle.standardError.write(Data(message.utf8))
        return 1
    }

    let payload = Array((command + "\n").utf8)
    _ = payload.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }

    var response = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = buffer.withUnsafeMutableBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            return read(fd, base, raw.count)
        }
        if n <= 0 { break }
        response.append(contentsOf: buffer[0..<n])
    }

    let text = String(data: response, encoding: .utf8) ?? ""
    print(text, terminator: "")
    return text.hasPrefix("status=0\n") ? 0 : 1
}

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
