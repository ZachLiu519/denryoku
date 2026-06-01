// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Denryoku",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "denryoku", targets: ["Denryoku"]),
        .library(name: "DenryokuKit", targets: ["DenryokuKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "DenryokuKit"
        ),
        .executableTarget(
            name: "Denryoku",
            dependencies: [
                "DenryokuKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        // Dependency-free self-test, runnable on any toolchain via
        // `swift run DenryokuSelfTest` (no XCTest/Xcode required).
        .executableTarget(
            name: "DenryokuSelfTest",
            dependencies: ["DenryokuKit"]
        )
    ]
)
