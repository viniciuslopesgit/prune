// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MaCClear",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MaCClear",
            path: "Sources/MaCClear",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
                .linkedFramework("Vision"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
