import Combine
import Foundation
import SwiftUI
import Testing
@testable import Prune

/// macOS 12 support: the app picks its interface path, ships for 12.0 and its models still tell
/// SwiftUI about changes now that they are ObservableObject instead of @Observable (macOS 14).
@Suite("macOS 12 compatibility")
struct CompatibilityTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test("macOS 12 (no Window/MenuBarExtra) always uses the AppKit interface")
    func legacyWithoutSceneAPIs() {
        #expect(PruneMain.usesLegacyUI(hasSceneAPIs: false, environment: [:]))
        #expect(PruneMain.usesLegacyUI(hasSceneAPIs: false, environment: ["PRUNE_LEGACY_UI": "0"]))
    }

    @Test("Newer macOS uses the SwiftUI scenes unless PRUNE_LEGACY_UI=1")
    func modernUnlessForced() {
        #expect(!PruneMain.usesLegacyUI(hasSceneAPIs: true, environment: [:]))
        #expect(!PruneMain.usesLegacyUI(hasSceneAPIs: true, environment: ["PRUNE_LEGACY_UI": "yes"]))
        #expect(PruneMain.usesLegacyUI(hasSceneAPIs: true, environment: ["PRUNE_LEGACY_UI": "1"]))
    }

    @Test("The tests run with the modern interface on this Mac")
    func currentChoice() {
        guard #available(macOS 13, *) else { return }
        #expect(PruneMain.legacyUI == (ProcessInfo.processInfo.environment["PRUNE_LEGACY_UI"] == "1"))
    }

    @Test("The menu bar title shows the CPU like MenuBarLabel")
    func menuBarTitle() {
        #expect(LegacyMenuBar.title(cpu: 0) == " 0%")
        #expect(LegacyMenuBar.title(cpu: 0.426) == " 42%")
        #expect(LegacyMenuBar.title(cpu: 1) == " 100%")
    }

    @Test("Open at login exists only where SMAppService exists")
    func launchAtLogin() {
        if #available(macOS 13, *) {
            #expect(AppSettings.launchAtLoginSupported)
        } else {
            #expect(!AppSettings.launchAtLoginSupported)
            #expect(!AppSettings.shared.launchAtLogin)
        }
    }

    @Test("Info.plist and Package.swift agree on macOS 12")
    func minimumVersion() throws {
        let plist = try #require(NSDictionary(contentsOf: Self.root.appendingPathComponent("Resources/Info.plist")))
        #expect(plist["LSMinimumSystemVersion"] as? String == "12.0")
        let package = try String(contentsOf: Self.root.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(package.contains(".macOS(.v12)"))
        let build = try String(contentsOf: Self.root.appendingPathComponent("scripts/build_app.sh"), encoding: .utf8)
        #expect(build.contains("LSMinimumSystemVersion"))
        #expect(!build.contains("macosx14"))
    }

    @Test("Models announce their changes to SwiftUI")
    @MainActor
    func modelsPublish() {
        var changes = 0
        var bag: Set<AnyCancellable> = []
        let shredder = ShredderModel()
        let largeFiles = LargeFilesModel()
        let uninstaller = UninstallerModel()
        let cleanup = CleanupModel(mode: { .trash }, scanner: { _ in [] })
        for publisher in [shredder.objectWillChange, largeFiles.objectWillChange,
                          uninstaller.objectWillChange, cleanup.objectWillChange] {
            publisher.sink { changes += 1 }.store(in: &bag)
        }
        shredder.items = [URL(fileURLWithPath: "/tmp/x")]
        largeFiles.selected = ["a"]
        uninstaller.search = "Safari"
        cleanup.progressText = "Scanning…"
        #expect(changes == 4)
    }

    @Test("A view becomes an image of the requested size")
    @MainActor
    func snapshot() {
        let image = Snapshot.image(Color.black, size: CGSize(width: 16, height: 16))
        #expect(image.size == CGSize(width: 16, height: 16))
        #expect(!image.representations.isEmpty)
    }
}
