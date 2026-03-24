// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftOpenShell",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SwiftOpenShell",
            targets: ["SwiftOpenShell"]
        ),
    ],
    targets: [
        .target(
            name: "SwiftOpenShell",
            path: "Sources/SwiftOpenShell",
            resources: [
                .copy("Resources/PolicyTemplates")
            ]
        ),
        .testTarget(
            name: "SwiftOpenShellTests",
            dependencies: ["SwiftOpenShell"],
            path: "Tests/SwiftOpenShellTests"
        ),
    ]
)
