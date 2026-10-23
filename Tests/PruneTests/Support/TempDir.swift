import Foundation
@testable import Prune

/// Isolated temporary folder for a test, deleted at the end (`deinit`).
/// Tests never touch files outside these folders.
final class TempDir {
    let url: URL

    init() throws {
        // scripts/pentest.sh points this at its isolated folder (the only place its sandbox lets them write).
        let base = ProcessInfo.processInfo.environment["PRUNE_TEST_TMP"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        url = (base ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("prune-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func path(_ name: String) -> URL { url.appendingPathComponent(name) }

    @discardableResult
    func file(_ name: String, _ text: String) throws -> URL {
        try file(name, Data(text.utf8))
    }

    @discardableResult
    func file(_ name: String, _ data: Data) throws -> URL {
        let u = path(name)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: u)
        return u
    }

    @discardableResult
    func file(_ name: String, bytes: Int, fill: UInt8) throws -> URL {
        try file(name, Data(repeating: fill, count: bytes))
    }

    @discardableResult
    func dir(_ name: String) throws -> URL {
        let u = path(name)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @discardableResult
    func symlink(_ name: String, to target: URL) throws -> URL {
        let u = path(name)
        try FileManager.default.createSymbolicLink(at: u, withDestinationURL: target)
        return u
    }
}

func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

func exists(_ url: URL) -> Bool {
    // `fileExists` follows links; here what matters is whether the entry itself exists.
    (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
}

/// Deterministic pseudo-random data (always the same for the same seed).
func noise(_ count: Int, seed: UInt64) -> Data {
    var state = seed &+ 0x9E37_79B9_7F4A_7C15
    var bytes = [UInt8](repeating: 0, count: count)
    for i in 0..<count {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        bytes[i] = UInt8(truncatingIfNeeded: state)
    }
    return Data(bytes)
}
