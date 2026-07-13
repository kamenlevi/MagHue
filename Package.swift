// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MagHue",
    platforms: [
        .macOS("14.0")
    ],
    targets: [
        // Code shared by the app and the privileged helper.
        .target(
            name: "MagHueCore",
            path: "Sources/MagHueCore"
        ),
        // Menu bar app.
        .executableTarget(
            name: "MagHue",
            dependencies: ["MagHueCore"],
            path: "Sources/MagHue"
        ),
        // Root launchd daemon that actually writes the SMC key.
        .executableTarget(
            name: "maghue-helper",
            dependencies: ["MagHueCore"],
            path: "Sources/MagHueHelper"
        ),
    ]
)
