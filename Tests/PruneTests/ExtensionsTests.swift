import Foundation
import Testing
@testable import Prune

func json(_ object: [String: Any]) throws -> Data {
    guard JSONSerialization.isValidJSONObject(object) else { throw CocoaError(.propertyListWriteInvalid) }
    return try JSONSerialization.data(withJSONObject: object)
}

@Suite("Browser extensions")
struct ExtensionsTests {
    static let chrome = "Library/Application Support/Google/Chrome"
    static let firefox = "Library/Application Support/Firefox/Profiles"

    @Test("Chromium: name, version, permissions and store origin from the newest version folder")
    func chromium() throws {
        let tmp = try TempDir()
        let ext = "\(Self.chrome)/Default/Extensions/abcdefgh"
        try tmp.file("\(ext)/1.0_0/manifest.json", try json(["name": "Old", "version": "1.0"]))
        try tmp.file("\(ext)/2.0_0/manifest.json", try json([
            "name": "__MSG_appName__", "version": "2.0", "default_locale": "en",
            "permissions": ["tabs", ["unexpected": 1]], "host_permissions": ["https://*/*"],
        ]))
        try tmp.file("\(ext)/2.0_0/_locales/en/messages.json", try json(["APPNAME": ["message": "Ad Blocker"]]))
        try tmp.file("\(Self.chrome)/Profile 2/Extensions/sideload/1.0/manifest.json", try json(["name": "Side", "version": "1"]))
        try tmp.file("\(Self.chrome)/Profile 2/Preferences", try json(["extensions": ["settings": ["sideload": ["from_webstore": false]]]]))
        let all = inFakeHome(tmp) { BrowserExtensions.scanAll() }
        let blocker = try #require(all.first { $0.identifier == "abcdefgh" })
        #expect(blocker.name == "Ad Blocker" && blocker.version == "2.0" && blocker.browser == "Google Chrome")
        #expect(blocker.permissions == ["tabs", "https://*/*"])
        #expect(blocker.url.lastPathComponent == "abcdefgh")
        let side = try #require(all.first { $0.identifier == "sideload" })
        #expect(!side.fromStore && side.browser == "Google Chrome · Profile 2")
    }

    @Test("A folder without a valid manifest is not an extension")
    func noManifest() throws {
        let tmp = try TempDir()
        try tmp.file("\(Self.chrome)/Default/Extensions/broken/1.0/manifest.json", "{not json")
        try tmp.dir("\(Self.chrome)/Default/Extensions/empty")
        #expect(inFakeHome(tmp) { BrowserExtensions.scanAll() }.isEmpty)
    }

    @Test("Firefox: profile extensions inside the profile are listed; app and system ones are not")
    func firefox() throws {
        let tmp = try TempDir()
        let profile = try tmp.dir("\(Self.firefox)/abc.default")
        let xpi = try tmp.file("\(Self.firefox)/abc.default/extensions/ublock@x.xpi", bytes: 10, fill: 1)
        let addons: [[String: Any]] = [
            ["id": "ublock@x", "type": "extension", "location": "app-profile", "path": xpi.path, "version": "1.6",
             "signedState": 2, "defaultLocale": ["name": "uBlock"], "userPermissions": ["origins": ["<all_urls>"]]],
            ["id": "sys@x", "type": "extension", "location": "app-system-defaults", "path": xpi.path],
            ["id": "theme@x", "type": "theme", "location": "app-profile", "path": xpi.path],
        ]
        try tmp.file("\(Self.firefox)/abc.default/extensions.json", try json(["addons": addons]))
        _ = profile
        let all = inFakeHome(tmp) { BrowserExtensions.scanAll() }
        #expect(all.map(\.identifier) == ["ublock@x"])
        #expect(all.first?.name == "uBlock" && all.first?.fromStore == true && all.first?.permissions == ["<all_urls>"])
    }
}
