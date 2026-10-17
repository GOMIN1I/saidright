// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Saidright",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Saidright", targets: ["Saidright"]),
        .library(name: "SaidrightCore", targets: ["SaidrightCore"]),
    ],
    targets: [
        // Platform-neutral logic: modes, session state, hotkey detection, prompts,
        // response validation, persistence and migration. No AppKit, no audio.
        .target(name: "SaidrightCore", path: "Sources/SaidrightCore"),
        .executableTarget(
            name: "Saidright",
            dependencies: ["SaidrightCore"],
            path: "Sources/Saidright",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Security"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .testTarget(name: "SaidrightCoreTests", dependencies: ["SaidrightCore"], path: "Tests/SaidrightCoreTests"),
    ]
)
