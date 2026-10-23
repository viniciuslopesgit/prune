import Foundation

/// `Prune --bench`: measures the memory (phys_footprint) of each heavy scan.
enum MemoryBench {
    static func footprint() -> (now: Int64, peak: Int64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return (0, 0) }
        return (Int64(info.phys_footprint), Int64(info.ledger_phys_footprint_peak))
    }

    static func runIfRequested() {
        guard CommandLine.arguments.contains("--bench") else { return }
        Task.detached {
            var keep: [Any] = []
            func step(_ name: String, _ f: () async -> Any) async {
                let before = footprint().now
                let t = Date()
                let r = await f()
                keep.append(r)
                let after = footprint()
                print(String(format: "%-34@ %6.1fs  before %6.1f MB  after %6.1f MB  peak %6.1f MB",
                             name as NSString, Date().timeIntervalSince(t),
                             Double(before) / 1e6, Double(after.now) / 1e6, Double(after.peak) / 1e6))
            }
            let p = ProgressReporter.silent
            print("Start: \(Double(footprint().now) / 1e6) MB")
            let rounds = CommandLine.arguments.contains("--twice") ? 2 : 1
            for round in 1...rounds {
            if rounds > 1 { print("— Round \(round) —") }
            await step("System Junk") { await SystemJunkScanner.scan(p) }
            await step("Privacy") { await PrivacyScanner.scan(p) }
            await step("Applications (+leftovers)") { () -> Any in
                let apps = AppScanner.installedApps()
                return (apps, apps.map { AppScanner.leftovers(for: $0) })
            }
            await step("Extensions") { await ExtensionService.systemExtensions() }
            await step("Large & Old Files (home)") { LargeFilesModel.find(in: [home], minSize: 10_000_000, includeLibrary: true, progress: p) }
            let roots = [URL.home("Downloads"), URL.home("Documents"), URL.home("Desktop"), URL.home("Pictures")]
            await step("Duplicates (4 folders)") { DuplicateFinder.find(in: roots, minSize: 100 * 1024, progress: p) }
            await step("Space Lens (home)") { SpaceScanner(progress: p).scan(home) }
            if CommandLine.arguments.contains("--photos") {
                await step("Similar photos (Pictures)") { DuplicateFinder.similarPhotos(in: [URL.home("Pictures")], threshold: 0.45, progress: p).groups }
            }
            if rounds > 1 { keep.removeAll() }
            }
            print("End: \(Double(footprint().now) / 1e6) MB, peak \(Double(footprint().peak) / 1e6) MB, \(keep.count) results kept")
            exit(0)
        }
    }
}
