// swift-tools-version:5.9
// PianoCore: platform-independent pitch detection, onset detection, lesson model,
// lesson state machine and keyboard geometry. No UIKit/AVFoundation here, so the
// whole package builds and tests with `swift test` on macOS (and on Linux).
import PackageDescription

let package = Package(
    name: "PianoCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PianoCore", targets: ["PianoCore"]),
    ],
    targets: [
        .target(
            name: "PianoCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PianoCoreTests",
            dependencies: ["PianoCore"]
        ),
    ]
)
