// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "patchbay",
  platforms: [.macOS("14.2")],
  products: [
    .executable(name: "patchbay", targets: ["patchbay"])
  ],
  targets: [
    .executableTarget(name: "patchbay")
  ]
)
