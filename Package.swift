// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Speakify",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Speakify", targets: ["Speakify"])
    ],
    targets: [
        .executableTarget(
            name: "Speakify",
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
