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

/// Executa AppleScript numa thread dedicada e sempre a mesma: o NSAppleScript não é seguro para
/// usar em várias threads, e não deve bloquear a thread principal (algumas tarefas demoram minutos).
final class AppleScriptRunner: NSObject, @unchecked Sendable {
    static let shared = AppleScriptRunner()

    private final class Job: NSObject {
        let source: String
        let done: (ShellResult) -> Void
        init(_ source: String, _ done: @escaping (ShellResult) -> Void) {
            self.source = source
            self.done = done
        }
    }

    private var thread: Thread!

    private override init() {
        super.init()
        let ready = DispatchSemaphore(value: 0)
        thread = Thread {
            RunLoop.current.add(NSMachPort(), forMode: .default)
            ready.signal()
            while true { RunLoop.current.run(mode: .default, before: .distantFuture) }
        }
        thread.name = "MaCClear.AppleScript"
        thread.qualityOfService = .userInitiated
        thread.start()
        ready.wait()
    }

    func run(_ source: String) async -> ShellResult {
        await withCheckedContinuation { cont in
            let job = Job(source) { cont.resume(returning: $0) }
            perform(#selector(execute(_:)), on: thread, with: job, waitUntilDone: false)
        }
    }

    @objc private func execute(_ job: Job) {
        var error: NSDictionary?
        let result = NSAppleScript(source: job.source)?.executeAndReturnError(&error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int ?? -1
            let message = error[NSAppleScript.errorMessage] as? String ?? "Erro"
            // -128 = o utilizador cancelou o pedido de palavra-passe.
            job.done(ShellResult(status: Int32(number), out: "", err: "\(message) (\(number))"))
        } else {
            job.done(ShellResult(status: 0, out: result?.stringValue ?? "", err: ""))
        }
    }
}
