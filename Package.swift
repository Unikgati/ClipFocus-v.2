// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipFocus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ClipFocusCore",
            targets: ["ClipFocusCore"]
        ),
        .executable(
            name: "ClipFocusApp",
            targets: ["ClipFocusApp"]
        ),
        .executable(
            name: "ClipFocusCLI",
            targets: ["ClipFocusCLI"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ClipFocusCore",
            dependencies: [],
            path: "Sources/ClipFocusCore"
        ),
        .executableTarget(
            name: "ClipFocusApp",
            dependencies: ["ClipFocusCore"],
            path: "Sources/ClipFocusApp"
        ),
        .executableTarget(
            name: "ClipFocusCLI",
            dependencies: ["ClipFocusCore"],
            path: "Sources/ClipFocusCLI"
        ),
        .testTarget(
            name: "ClipFocusCoreTests",
            dependencies: ["ClipFocusCore"],
            path: "Tests/ClipFocusCoreTests"
        )
    ]
)
