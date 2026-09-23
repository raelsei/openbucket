// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OpenBucket",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "OpenBucketCore", targets: ["OpenBucketCore"]),
    ],
    targets: [
        .target(name: "OpenBucketCore"),
        .testTarget(name: "OpenBucketCoreTests", dependencies: ["OpenBucketCore"]),
    ]
)
