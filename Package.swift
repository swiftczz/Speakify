// swift-tools-version: 6.2

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility")
]

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
            ],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "SpeakifyApp",
            dependencies: ["Speakify"],
            path: "Sources/SpeakifyApp",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SpeakifyTests",
            dependencies: ["Speakify"],
            swiftSettings: swiftSettings
        )
    ]
)
