// swift-tools-version:5.9
// Test harness for Orbit's pure logic (parsers, matching, attention ranking).
// The app target compiles the same files from Orbit/Core via Xcode's synced
// folder; this package exists so they can be tested with `swift test`.
import PackageDescription

let package = Package(
    name: "OrbitCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "OrbitCore", targets: ["OrbitCore"]),
    ],
    targets: [
        .target(name: "OrbitCore", path: "Orbit/Core"),
        .testTarget(name: "OrbitCoreTests", dependencies: ["OrbitCore"], path: "Tests/OrbitCoreTests"),
    ]
)
