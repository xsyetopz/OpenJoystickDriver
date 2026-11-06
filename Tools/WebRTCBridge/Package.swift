// swift-tools-version: 6.4
import PackageDescription

/// The `ojd-webrtc-bridge` tool, which joins two endpoints over a WebRTC data channel.
let package = Package(
  name: "WebRTCBridge",
  platforms: [.macOS(.v12)],
  products: [.executable(name: "ojd-webrtc-bridge", targets: ["WebRTCBridge"])],
  dependencies: [
    .package(path: "../BridgeCore"),
    .package(url: "https://github.com/livekit/webrtc-xcframework.git", exact: "150.7871.03"),
  ],
  targets: [
    .target(
      name: "WebRTCBridgeCore",
      dependencies: [
        .product(name: "BridgeCore", package: "BridgeCore"),
        .product(name: "LiveKitWebRTC", package: "webrtc-xcframework"),
      ]
    ),
    .executableTarget(name: "WebRTCBridge", dependencies: ["WebRTCBridgeCore"]),
    .testTarget(
      name: "WebRTCBridgeCoreTests",
      dependencies: [
        "WebRTCBridge", "WebRTCBridgeCore", .product(name: "BridgeCore", package: "BridgeCore"),
      ]
    ),
  ],
  swiftLanguageModes: [.v5]
)

// Warnings are errors in every target of this package; the setting does not reach dependencies.
for target in package.targets {
  target.swiftSettings = (target.swiftSettings ?? []) + [.treatAllWarnings(as: .error)]
}
