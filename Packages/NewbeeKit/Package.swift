// swift-tools-version: 6.0
// NewbeeKit: platform-independent domain logic (session engine, analytics, export).
// Must build and test on Linux: Foundation only, no Apple UI or persistence frameworks.
import PackageDescription

let package = Package(
    name: "NewbeeKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "NewbeeKit", targets: ["NewbeeKit"]),
    ],
    targets: [
        .target(name: "NewbeeKit"),
        .testTarget(name: "NewbeeKitTests", dependencies: ["NewbeeKit"]),
    ]
)
