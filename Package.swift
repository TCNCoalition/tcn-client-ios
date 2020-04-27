// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TCNClient",
    platforms: [
      .iOS(.v12),
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "TCNClient",
            targets: ["TCNClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pebble8888/ed25519swift.git", from: "1.2.5")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "TCNClient",
            dependencies: ["ed25519swift"]),
        .testTarget(
            name: "TCNClientTests",
            dependencies: ["TCNClient"]),
    ]
)
