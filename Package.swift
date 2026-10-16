// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Saywell",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Saywell", targets: ["Saywell"]),
        .library(name: "SaywellCore", targets: ["SaywellCore"]),
    ],
    targets: [
        // Platform-neutral logic: modes, session state, hotkey detection, prompts,
        // response validation, persistence and migration. No AppKit, no audio.
        .target(name: "SaywellCore", path: "Sources/SaywellCore"),
        .executableTarget(
            name: "Saywell",
            dependencies: ["SaywellCore"],
            path: "Sources/Saywell",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Security"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .testTarget(name: "SaywellCoreTests", dependencies: ["SaywellCore"], path: "Tests/SaywellCoreTests"),
    ]
)
