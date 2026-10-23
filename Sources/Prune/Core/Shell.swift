import Foundation

struct ShellResult {
    let status: Int32
    let out: String
    let err: String
    var ok: Bool { status == 0 }
}

/// Runs external commands without blocking the interface.
enum Shell {
    @discardableResult
    static func run(_ launchPath: String, _ args: [String] = [], env: [String: String]? = nil) async -> ShellResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: runSync(launchPath, args, env: env))
            }
        }
    }

    static func runSync(_ launchPath: String, _ args: [String] = [], env: [String: String]? = nil) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        if let env {
            process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        }
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ShellResult(status: -1, out: "", err: error.localizedDescription)
        }
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        return ShellResult(
            status: process.terminationStatus,
            out: String(decoding: outData, as: UTF8.self),
            err: String(decoding: errData, as: UTF8.self)
        )
    }

    /// Runs a zsh script as the current user.
    @discardableResult
    static func zsh(_ script: String) async -> ShellResult {
        await run("/bin/zsh", ["-c", script])
    }

    /// Runs a script with administrator privileges (macOS asks for the password).
    ///
    /// Runs inside the process itself (NSAppleScript), on a dedicated thread. Note: recent macOS
    /// (tested on 27) does not remember this authorization — it asks for the password on every run.
    /// `without altering line endings` keeps line breaks as `\n`.
    @discardableResult
    static func admin(_ script: String) async -> ShellResult {
        let apple = "do shell script \"\(appleScriptEscape(script))\" with administrator privileges without altering line endings"
        return await AppleScriptRunner.shared.run(apple)
    }

    static func osascript(_ source: String) async -> ShellResult {
        await run("/usr/bin/osascript", ["-e", source])
    }

    /// Shell-safe single quotes.
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    static var uid: uid_t { getuid() }

    static func which(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
