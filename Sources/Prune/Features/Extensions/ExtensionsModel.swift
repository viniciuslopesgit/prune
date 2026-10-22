import AppKit
import Observation

@MainActor
@Observable
final class ExtensionsModel {
    var category: ExtensionCategory = .safari
    var system: [SystemExtension] = []
    var browser: [BrowserExtension] = []
    var files: [ExtensionCategory: [PluginFile]] = [:]
    var showSystem = false
    var loading = false
    var loaded = false
    var message: String?

    func load() async {
        loading = true
        async let s = ExtensionService.systemExtensions()
        let b = await Task.detached { BrowserExtensions.scanAll() }.value
        let f = await Task.detached { ExtensionService.pluginFiles() }.value
        system = await s
        browser = b
        files = f
        loading = false
        loaded = true
    }

    func extensions(in cat: ExtensionCategory) -> [SystemExtension] {
        system.filter { ExtensionCategory.from(sdk: $0.sdk) == cat && (showSystem || !$0.isSystem) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func count(_ cat: ExtensionCategory) -> Int {
        switch cat {
        case .browsers: browser.count
        case .prefPanes, .plugins: files[cat]?.count ?? 0
        default: extensions(in: cat).count + (files[cat]?.count ?? 0)
        }
    }

    func toggle(_ ext: SystemExtension) async {
        let ok = await ExtensionService.setEnabled(ext, !ext.enabled)
        if ok, let i = system.firstIndex(where: { $0.id == ext.id }) { system[i].enabled.toggle() }
        if !ok { message = "Não foi possível alterar \(ext.name)." }
    }

    func remove(_ ext: BrowserExtension) async {
        let bundleIDs = PrivacyScanner.browserBundleIDs.filter { ext.browser.hasPrefix($0.value) }.map(\.key)
        if bundleIDs.contains(where: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }) {
            message = "Feche o \(ext.browser) para remover a extensão."
            return
        }
        let r = await Cleaner.remove(urls: [ext.url], mode: .trash)
        if r.failed.isEmpty { browser.removeAll { $0.id == ext.id } } else { message = "Não foi possível remover \(ext.name)." }
    }

    func remove(_ file: PluginFile, category: ExtensionCategory) async {
        var r = await Cleaner.remove(urls: [file.url], mode: .trash)
        if !r.failed.isEmpty { r = await Cleaner.retryAsAdmin([file.url], mode: .trash) }
        if r.failed.isEmpty { files[category]?.removeAll { $0.id == file.id } } else { message = "Não foi possível remover \(file.url.lastPathComponent)." }
    }
}
