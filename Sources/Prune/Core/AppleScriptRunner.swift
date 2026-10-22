import Foundation

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
        thread.name = "Prune.AppleScript"
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
