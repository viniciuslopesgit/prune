import Foundation

/// Envia mensagens de progresso para a interface sem a sobrecarregar.
final class ProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast
    private let handler: @MainActor (String) -> Void

    init(_ handler: @escaping @MainActor (String) -> Void) { self.handler = handler }

    func report(_ text: String, force: Bool = false) {
        lock.lock()
        let now = Date()
        guard force || now.timeIntervalSince(last) > 0.08 else { lock.unlock(); return }
        last = now
        lock.unlock()
        Task { @MainActor in handler(text) }
    }

    static let silent = ProgressReporter { _ in }
}

extension Task where Success == Never, Failure == Never {
    static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
