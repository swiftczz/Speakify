// swift-tools-version: 6.2

import PackageDescription

// Swift 6 language mode is already the default at this tools version, so strict
// concurrency is on. These are the checks that are still opt-in: `ExistentialAny`
// forces `any` on existentials, and `MemberImportVisibility` stops a file using
// declarations from a module it never imported itself.
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
