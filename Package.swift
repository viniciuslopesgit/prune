// swift-tools-version:5.10
import Foundation
import PackageDescription

var targets: [Target] = [
    .executableTarget(
        name: "Prune",
        path: "Sources/Prune",
        linkerSettings: [
            .linkedFramework("IOKit"),
            .linkedFramework("Security"),
            .linkedFramework("Vision"),
            .linkedFramework("ServiceManagement"),
        ]
    ),
]

// Unit tests (scripts/test.sh). They test the executable directly with @testable import.
// They only exist on the dev branch: main only has what is needed to build the stable version.
if FileManager.default.fileExists(atPath: Context.packageDirectory + "/Tests/PruneTests") {
    targets.append(.testTarget(name: "PruneTests", dependencies: ["Prune"], path: "Tests/PruneTests"))
}

let package = Package(
    name: "Prune",
    platforms: [.macOS(.v14)],
    targets: targets
)
