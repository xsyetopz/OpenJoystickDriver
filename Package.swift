// swift-tools-version:6.2
import Foundation
import PackageDescription

let useLocalSwiftUSB = ProcessInfo.processInfo.environment["OJD_USE_LOCAL_SWIFTUSB"] == "1"
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let localSwiftUSBPath = packageDirectory.appendingPathComponent("../SwiftUSB").standardizedFileURL
  .path
let swiftUSBDependency: Package.Dependency =
  useLocalSwiftUSB && FileManager.default.fileExists(atPath: localSwiftUSBPath)
  ? .package(path: localSwiftUSBPath)
  : .package(url: "https://github.com/xsyetopz/SwiftUSB.git", exact: "0.1.2")
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
  platforms: [.macOS(.v10_15)],
  products: [.library(name: "OpenJoystickDriverKit", targets: ["OpenJoystickDriverKit"])],
  dependencies: [
    swiftUSBDependency, swifterKitDependency,
  ],
  targets: [
    .target(
      name: "OpenJoystickDriverKit",
      dependencies: [.product(name: "SwiftUSB", package: "SwiftUSB")],
      path: "Sources/OpenJoystickDriverKit",
      resources: [.process("Resources/")],
      linkerSettings: [.linkedFramework("ServiceManagement")]
    ),

    .target(
      name: "OpenJoystickDriverRelay",
      dependencies: ["OpenJoystickDriverKit", .product(name: "SwifterKit", package: "SwifterKit")],
      path: "Sources/OpenJoystickDriverRelay",
      linkerSettings: [.linkedFramework("IOKit")]
    ),

    .executableTarget(
      name: "DriverKitGenerator",
      dependencies: [
        "OpenJoystickDriverRelay", .product(name: "SwifterKit", package: "SwifterKit"),
      ],
      path: "Sources/DriverKitGenerator"
    ),

    .executableTarget(
      name: "OpenJoystickDriver",
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverRelay",
      ],
      path: "Sources/OpenJoystickDriver",
      exclude: ["App/Host.entitlements", "App/Info.plist"],
      resources: [.copy("Resources")],
      linkerSettings: [
        .linkedFramework("GameController"), .linkedFramework("SystemExtensions"),
      ]
    ),

    .executableTarget(
      name: "OpenJoystickDriverHIDTool",
      dependencies: ["OpenJoystickDriverKit", .product(name: "SwiftUSB", package: "SwiftUSB")],
      path: "Sources/OpenJoystickDriverHIDTool"
    ),

    .executableTarget(
      name: "OpenJoystickDriverGameControllerProbe",
      path: "Sources/OpenJoystickDriverGameControllerProbe",
      linkerSettings: [.linkedFramework("CoreHaptics"), .linkedFramework("GameController")]
    ),

    .testTarget(
      name: "OpenJoystickDriverKitTests",
      dependencies: ["OpenJoystickDriverKit", .product(name: "SwiftUSB", package: "SwiftUSB")],
      path: "Tests/OpenJoystickDriverKitTests",
      swiftSettings: [.unsafeFlags(["-target", testTargetTriple])],
      linkerSettings: [.unsafeFlags(["-target", testTargetTriple])]
    ),
    .testTarget(
      name: "OpenJoystickDriverRelayTests",
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverRelay",
        .product(name: "SwifterKit", package: "SwifterKit"),
      ],
      path: "Tests/OpenJoystickDriverRelayTests",
      swiftSettings: [.unsafeFlags(["-target", testTargetTriple])],
      linkerSettings: [.unsafeFlags(["-target", testTargetTriple])]
    ),
    .testTarget(
      name: "OpenJoystickDriverTests",
      dependencies: ["OpenJoystickDriver"],
      path: "Tests/OpenJoystickDriverTests",
      swiftSettings: [.unsafeFlags(["-target", testTargetTriple])],
      linkerSettings: [.unsafeFlags(["-target", testTargetTriple])]
    ),
  ]
)
