// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SystemEQ",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SystemEQ", targets: ["SystemEQ"])
    ],
    targets: [
        .executableTarget(
            name: "SystemEQ",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "SystemEQTests",
            dependencies: ["SystemEQ"]
        )
    ],
    swiftLanguageModes: [.v5]
)
