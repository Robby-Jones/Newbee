// swift-tools-version: 6.0
// NewbeeShared: code linked by BOTH the app and the widget extension
// (Live Activity attributes and planning, intent routing, design tokens).
// UI code is guarded by canImport(UIKit)/canImport(ActivityKit); the rest builds on Linux.
import PackageDescription

let package = Package(
    name: "NewbeeShared",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "NewbeeShared", targets: ["NewbeeShared"]),
    ],
    dependencies: [
        .package(path: "../NewbeeKit"),
    ],
    targets: [
        .target(name: "NewbeeShared", dependencies: ["NewbeeKit"]),
        // Live Activity mapping and planning are plain Swift and run on Linux too.
        .testTarget(name: "NewbeeSharedTests", dependencies: ["NewbeeShared"]),
    ]
)
