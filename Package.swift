// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "sshido",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "sshidoModels", targets: ["sshidoModels"]),
        .library(name: "sshidoCore",   targets: ["sshidoCore"]),
        .library(name: "sshidoUI",     targets: ["sshidoUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/orlandos-nl/Citadel", from: "0.12.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
    ],
    targets: [
        .target(name: "sshidoModels", path: "Sources/Models"),
        .target(
            name: "sshidoCore",
            dependencies: [
                "sshidoModels",
                .product(name: "Citadel", package: "Citadel"),
            ],
            path: "Sources/Core"
        ),
        .target(
            name: "sshidoUI",
            dependencies: [
                "sshidoModels",
                "sshidoCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/UI",
            resources: [.process("Metal/Shaders.metal")]
        ),
        .testTarget(
            name: "sshidoCoreTests",
            dependencies: ["sshidoCore", "sshidoModels"],
            path: "Tests/sshidoCoreTests"
        ),
    ]
)
