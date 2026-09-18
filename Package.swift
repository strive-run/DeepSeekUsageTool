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
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit")
            ]
        ),
        .testTarget(
            name: "DeepSeekUsageTests",
            dependencies: ["DeepSeekUsage"],
            swiftSettings: [
                // 无 Xcode（仅 CommandLineTools）环境下，Swift Testing 需要显式框架搜索路径
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ])
            ]
        )
    ]
)
