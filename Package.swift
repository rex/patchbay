// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "patchbay",
  // Process taps need 14.2; the lock-free ring buffer's Atomic needs 15.
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "patchbay", targets: ["patchbay"])
  ],
  targets: [
    .target(name: "PatchbayCore"),
    .executableTarget(name: "patchbay", dependencies: ["PatchbayCore"]),
    .testTarget(name: "PatchbayCoreTests", dependencies: ["PatchbayCore"]),
  ]
)
