// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Prune",
    platforms: [.macOS(.v14)],
    targets: [
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
        // Testes de unidade (scripts/test.sh). Testam o executável diretamente com @testable import.
        .testTarget(
            name: "PruneTests",
            dependencies: ["Prune"],
            path: "Tests/PruneTests"
        ),
    ]
)
