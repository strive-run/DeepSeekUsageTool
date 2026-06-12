// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DeepSeekUsage",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "DeepSeekUsage", targets: ["DeepSeekUsage"])
    ],
    targets: [
        .executableTarget(
            name: "DeepSeekUsage",
            swiftSettings: [
                .unsafeFlags(["-target", "arm64-apple-macosx26.0"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit")
            ]
        ),
        .testTarget(
            name: "DeepSeekUsageTests",
            dependencies: ["DeepSeekUsage"]
        )
    ]
)
