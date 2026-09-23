// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "OpenBucket",
  platforms: [.macOS("26.0")],
  products: [
    .library(name: "OpenBucketCore", targets: ["OpenBucketCore"]),
    .library(name: "OpenBucketS3", targets: ["OpenBucketS3"]),
  ],
  dependencies: [
    .package(url: "https://github.com/soto-project/soto.git", exact: "7.15.0"),
    .package(url: "https://github.com/soto-project/soto-core.git", exact: "7.15.0"),
  ],
  targets: [
    .target(name: "OpenBucketCore"),
    .target(
      name: "OpenBucketS3",
      dependencies: [
        "OpenBucketCore",
        .product(name: "SotoS3", package: "soto"),
        .product(name: "SotoCore", package: "soto-core"),
      ]
    ),
    .testTarget(name: "OpenBucketCoreTests", dependencies: ["OpenBucketCore"]),
    .testTarget(
      name: "OpenBucketS3Tests",
      dependencies: [
        "OpenBucketS3",
        "OpenBucketCore",
        .product(name: "SotoCore", package: "soto-core"),
      ]),
  ]
)
