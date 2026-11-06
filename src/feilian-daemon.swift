import Foundation
import Darwin

// Root LaunchDaemon for the FeiLian control helper.
//
// Security model:
// - Only accepts "stop" and "start".
// - Only accepts connections from the current console user's UID.
// - Only accepts connections whose executable is the installed feilian-auth binary.
// - Runs fixed, root-owned scripts. Never accepts a command or path from the client.

let socketPath = "/var/run/com.feiliancontrol.helper.sock"
let scriptDir = "/usr/local/libexec/feilian"
let clientPath = scriptDir + "/feilian-auth"
let allowedScripts: [String: String] = [
    "stop": scriptDir + "/stop.sh",
    "start": scriptDir + "/start.sh"
]

@_silgen_name("proc_pidpath")
func proc_pidpath(_ pid: Int32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: UInt32) -> Int32

func log(_ message: String) {
    let formatter = ISO8601DateFormatter()
    let line = "[\(formatter.string(from: Date()))] \(message)\n"
    FileHandle.standardError.write(Data(line.utf8))
}

func currentConsoleUID() -> uid_t {
    if let attrs = try? FileManager.default.attributesOfItem(atPath: "/dev/console"),
       let uid = attrs[.ownerAccountID] as? NSNumber {
        return uid.uint32Value
    }
    return 0
}

func peerExecutablePath(_ fd: Int32) -> String? {
    var pid: pid_t = 0
    var len = socklen_t(MemoryLayout<pid_t>.size)
    guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &len) == 0, pid > 0 else {
        return nil
    }
    var buffer = [CChar](repeating: 0, count: 4096)
    let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard n > 0 else { return nil }
    return String(cString: buffer)
}

func resolvedPath(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
}

func writeAll(_ fd: Int32, _ string: String) {
    let bytes = Array(string.utf8)
    bytes.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return }
        var offset = 0
        while offset < raw.count {
            let n = write(fd, base.advanced(by: offset), raw.count - offset)
            if n <= 0 { break }
            offset += n
        }
    }
}

func runScript(_ path: String) -> (String, Int32) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [path]
    process.environment = [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "LANG": "en_US.UTF-8"
    ]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (output, process.terminationStatus)
    } catch {
        return ("failed to run \(path): \(error)\n", 1)
    }
}

func handleClient(_ fd: Int32) {
    defer { close(fd) }

    var timeout = timeval(tv_sec: 60, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    var uid: uid_t = 0
    var gid: gid_t = 0
    guard getpeereid(fd, &uid, &gid) == 0 else { return }

    let consoleUID = currentConsoleUID()
    guard uid == consoleUID || uid == 0 else {
        log("rejected peer uid \(uid), console uid \(consoleUID)")
        writeAll(fd, "unauthorized\n")
        return
    }

    guard let peerPath = peerExecutablePath(fd) else {
        log("rejected peer uid \(uid): cannot determine executable path")
        writeAll(fd, "unauthorized\n")
        return
    }
    guard resolvedPath(peerPath) == resolvedPath(clientPath) else {
        log("rejected peer executable \(peerPath)")
        writeAll(fd, "unauthorized\n")
        return
    }

    var buffer = [UInt8](repeating: 0, count: 128)
    let n = buffer.withUnsafeMutableBytes { raw -> Int in
        guard let base = raw.baseAddress else { return 0 }
        return read(fd, base, raw.count)
    }
    guard n > 0 else { return }

    let command = String(bytes: buffer[0..<n], encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard let script = allowedScripts[command] else {
        log("rejected command from uid \(uid)")
        writeAll(fd, "unknown command\n")
        return
    }

    log("running \(command) for uid \(uid)")
    let (output, status) = runScript(script)
    log("\(command) finished with status \(status)")
    writeAll(fd, "status=\(status)\n\(output)")
}

unlink(socketPath)
let server = socket(AF_UNIX, SOCK_STREAM, 0)
guard server >= 0 else { perror("socket"); exit(1) }

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

let bindResult = withUnsafePointer(to: &addr) { ptr in
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard bindResult == 0 else { perror("bind"); exit(1) }

// The socket is reachable by local processes, but handleClient rejects any
// process that is not the current console user running feilian-auth.
chmod(socketPath, 0o666)

guard listen(server, 10) == 0 else { perror("listen"); exit(1) }
signal(SIGPIPE, SIG_IGN)
log("listening on \(socketPath)")

while true {
    let client = accept(server, nil, nil)
    if client < 0 { continue }
    handleClient(client)
}
