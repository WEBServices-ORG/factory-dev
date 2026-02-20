// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "dev",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "dev", targets: ["dev"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    .package(url: "https://github.com/apple/swift-log", from: "1.10.1"),
  ],
  targets: [
    .executableTarget(
      name: "dev",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Logging", package: "swift-log"),
      ]
    )
  ]
)
