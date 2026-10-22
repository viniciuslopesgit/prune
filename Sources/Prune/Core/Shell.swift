import Foundation

struct ShellResult {
    let status: Int32
    let out: String
    let err: String
    var ok: Bool { status == 0 }
}

/// Executa comandos externos sem bloquear a interface.
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

    /// Executa um script zsh como o utilizador atual.
    @discardableResult
    static func zsh(_ script: String) async -> ShellResult {
        await run("/bin/zsh", ["-c", script])
    }

    /// Executa um script com privilégios de administrador (o macOS pede a palavra-passe).
    ///
    /// Corre dentro do próprio processo (NSAppleScript), numa thread dedicada. Nota: o macOS recente
    /// (testado no 27) não memoriza esta autorização — pede a palavra-passe em cada execução.
    /// `without altering line endings` mantém as quebras de linha em `\n`.
    @discardableResult
    static func admin(_ script: String) async -> ShellResult {
        let apple = "do shell script \"\(appleScriptEscape(script))\" with administrator privileges without altering line endings"
        return await AppleScriptRunner.shared.run(apple)
    }

    static func osascript(_ source: String) async -> ShellResult {
        await run("/usr/bin/osascript", ["-e", source])
    }

    /// Aspas simples seguras para shell.
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
