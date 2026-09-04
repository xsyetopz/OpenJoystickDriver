// swift-tools-version:6.3.0
import PackageDescription

let package = Package(
  name: "HapticsBackendProbe",
  platforms: [.macOS(.v10_15)],
  dependencies: [.package(path: "../..")],
  targets: [
    .executableTarget(
      name: "HapticsBackendProbe",
      dependencies: [.product(name: "OpenJoystickDriverKit", package: "OpenJoystickDriver")],
      linkerSettings: [
        .linkedFramework("CoreHaptics"), .linkedFramework("ForceFeedback"),
        .linkedFramework("GameController"), .linkedFramework("IOKit")
      ]
    )
  ]
)
