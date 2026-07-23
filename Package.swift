// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Speakify",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Speakify", targets: ["SpeakifyApp"])
    ],
    targets: [
        .target(
            name: "Speakify",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "SpeakifyApp",
            dependencies: ["Speakify"],
            path: "Sources/SpeakifyApp",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "SpeakifyTests",
            dependencies: ["Speakify"]
        )
    ]
)
