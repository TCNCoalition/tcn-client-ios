// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TCNClient",
    platforms: [
        // TODO: Add support for iOS 12.
      .iOS(.v12),
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "TCNClient",
            targets: ["TCNClient"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/TCNCoalition/CryptoKit25519", from: "0.6.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "TCNClient",
            dependencies: ["CryptoKit25519"]),
        .testTarget(
            name: "TCNClientTests",
            dependencies: ["TCNClient", "CryptoKit25519"]),
    ]
)
