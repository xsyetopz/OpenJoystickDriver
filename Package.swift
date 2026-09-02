// swift-tools-version:6.2
import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let useLocalSwifterKit = ProcessInfo.processInfo.environment["OJD_USE_LOCAL_SWIFTERKIT"] == "1"
let localSwifterKitPath = packageDirectory.appendingPathComponent("../SwifterKit")
  .standardizedFileURL.path
let swifterKitDependency: Package.Dependency =
  useLocalSwifterKit && FileManager.default.fileExists(atPath: localSwifterKitPath)
  ? .package(path: localSwifterKitPath)
  : .package(url: "https://github.com/xsyetopz/SwifterKit.git", branch: "main")

#if arch(arm64)
  let testTargetTriple = "arm64-apple-macosx14.0"
#elseif arch(x86_64)
  let testTargetTriple = "x86_64-apple-macosx14.0"
#else
  #error("Unsupported host architecture for Swift Testing target triple")
#endif

let package = Package(
  name: "OpenJoystickDriver",
  defaultLocalization: "en-US",
  platforms: [.macOS(.v10_15)],
  products: [.library(name: "OpenJoystickDriverKit", targets: ["OpenJoystickDriverKit"])],
  dependencies: [swifterKitDependency],
  targets: [
    .target(
      name: "OpenJoystickDriverKit",
      dependencies: [],
      path: "Sources/OpenJoystickDriverKit",
      resources: [.process("Resources/")],
      linkerSettings: [
        .linkedFramework("ServiceManagement"),
        .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "CoreHID"])
      ]
    ),

    .target(
      name: "OpenJoystickDriverUSB",
      dependencies: ["OpenJoystickDriverKit", .product(name: "SwifterKit", package: "SwifterKit")],
      path: "Sources/OpenJoystickDriverUSB",
      linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("IOUSBHost")]
    ),

    .executableTarget(
      name: "DriverKitGenerator",
      dependencies: ["OpenJoystickDriverUSB", .product(name: "SwifterKit", package: "SwifterKit")],
      path: "Sources/DriverKitGenerator",
      exclude: ["Entitlements"]
    ),

    .executableTarget(
      name: "OpenJoystickDriver",
      dependencies: ["OpenJoystickDriverKit", "OpenJoystickDriverUSB"],
      path: "Sources/OpenJoystickDriver",
      exclude: ["App/Host.entitlements", "App/Info.plist"],
      resources: [.copy("Resources")],
      linkerSettings: [.linkedFramework("GameController"), .linkedFramework("SystemExtensions")]
    ),

    .executableTarget(
      name: "OpenJoystickDriverHIDTool",
      dependencies: ["OpenJoystickDriverKit", "OpenJoystickDriverUSB"],
      path: "Sources/OpenJoystickDriverHIDTool"
    ),

    .executableTarget(
      name: "OpenJoystickDriverGameControllerProbe",
      dependencies: ["OpenJoystickDriverKit"],
      path: "Sources/OpenJoystickDriverGameControllerProbe",
      linkerSettings: [.linkedFramework("CoreHaptics"), .linkedFramework("GameController")]
    ),

    .testTarget(
      name: "OpenJoystickDriverKitTests",
      dependencies: ["OpenJoystickDriverKit", "OpenJoystickDriverUSB"],
      path: "Tests/OpenJoystickDriverKitTests",
      swiftSettings: [.unsafeFlags(["-target", testTargetTriple])],
      linkerSettings: [.unsafeFlags(["-target", testTargetTriple])]
    ),
    .testTarget(
      name: "OpenJoystickDriverUSBTests",
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverUSB",
        .product(name: "SwifterKit", package: "SwifterKit")
      ],
      path: "Tests/OpenJoystickDriverUSBTests",
      swiftSettings: [.unsafeFlags(["-target", testTargetTriple])],
      linkerSettings: [.unsafeFlags(["-target", testTargetTriple])]
    ),
    .testTarget(
      name: "OpenJoystickDriverTests",
      dependencies: ["OpenJoystickDriver"],
      path: "Tests/OpenJoystickDriverTests",
      swiftSettings: [.unsafeFlags(["-target", testTargetTriple])],
      linkerSettings: [.unsafeFlags(["-target", testTargetTriple])]
    )
  ]
)
