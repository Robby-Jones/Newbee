// swift-tools-version: 6.0
// NewbeeShared: code linked by BOTH the app and the widget extension
// (Live Activity attributes, App Intents, design tokens). iOS only.
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
    ]
)
