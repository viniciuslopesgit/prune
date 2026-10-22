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

// Testes de unidade (scripts/test.sh). Testam o executável diretamente com @testable import.
// Só existem no ramo dev: o main tem apenas o necessário para compilar a versão estável.
if FileManager.default.fileExists(atPath: Context.packageDirectory + "/Tests/PruneTests") {
    targets.append(.testTarget(name: "PruneTests", dependencies: ["Prune"], path: "Tests/PruneTests"))
}

let package = Package(
    name: "Prune",
    platforms: [.macOS(.v14)],
    targets: targets
)
