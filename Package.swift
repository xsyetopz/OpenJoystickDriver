// swift-tools-version:6.2
import Foundation
import PackageDescription

let useLocalSwiftUSB = ProcessInfo.processInfo.environment["OJD_USE_LOCAL_SWIFTUSB"] == "1"
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let localSwiftUSBPath = packageDirectory
  .appendingPathComponent("../SwiftUSB")
  .standardizedFileURL
  .path
let swiftUSBDependency: Package.Dependency =
  useLocalSwiftUSB && FileManager.default.fileExists(atPath: localSwiftUSBPath)
    ? .package(path: localSwiftUSBPath)
    : .package(url: "https://github.com/xsyetopz/SwiftUSB.git", from: "0.1.0")

#if arch(arm64)
let testTargetTriple = "arm64-apple-macosx26.0"
#elseif arch(x86_64)
let testTargetTriple = "x86_64-apple-macosx26.0"
#else
#error("Unsupported host architecture for Swift Testing target triple")
#endif

let package = Package(
  name: "OpenJoystickDriver",
  defaultLocalization: "en-US",
  platforms: [.macOS(.v10_15)],
  products: [
    .library(name: "OpenJoystickDriverKit", targets: ["OpenJoystickDriverKit"]),
  ],
  dependencies: [
    swiftUSBDependency,
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3"),
  ],
  targets: [
    .systemLibrary(
      name: "CSDL3",
      path: "Sources/CSDL3",
      pkgConfig: "sdl3",
    ),

    .target(
      name: "OJDSDL3Shim",
      dependencies: ["CSDL3"],
      path: "Sources/OJDSDL3Shim",
      publicHeadersPath: "include"
    ),

    .target(
      name: "OpenJoystickDriverKit",
      dependencies: [
        "OJDSDL3Shim",
        .product(name: "SwiftUSB", package: "SwiftUSB"),
      ],
      path: "Sources/OpenJoystickDriverKit",
      resources: [.process("Resources/")],
      linkerSettings: [
        .linkedFramework("ServiceManagement"),
      ]
    ),

    .executableTarget(
      name: "OpenJoystickDriverDaemon",
      dependencies: ["OpenJoystickDriverKit"],
      path: "Sources/OpenJoystickDriverDaemon",
      exclude: ["OpenJoystickDriverDaemon.entitlements.template"],
      linkerSettings: [
        .linkedFramework("GameController"),
        .unsafeFlags([
          "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
          "-Xlinker", "-rpath", "-Xlinker", "/opt/homebrew/lib",
        ]),
      ]
    ),

    .executableTarget(
      name: "OpenJoystickDriver",
      dependencies: [
        "OpenJoystickDriverKit",
        .product(name: "Sparkle", package: "Sparkle"),
      ],
      path: "Sources/OpenJoystickDriver",
      exclude: [
        "OpenJoystickDriver.entitlements.template",
        "App/Info.plist",
        "App/com.openjoystickdriver.daemon.plist",
      ],
      resources: [.copy("Resources")],
      linkerSettings: [
        .linkedFramework("SystemExtensions"),
        .unsafeFlags([
          "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
          "-Xlinker", "-rpath", "-Xlinker", "/opt/homebrew/lib",
        ]),
      ]
    ),

    .executableTarget(
      name: "OpenJoystickDriverHIDTool",
      dependencies: [
        "OpenJoystickDriverKit",
        .product(name: "SwiftUSB", package: "SwiftUSB"),
      ],
      path: "Sources/OpenJoystickDriverHIDTool",
      linkerSettings: [
        .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/opt/homebrew/lib"])
      ]
    ),

    .executableTarget(
      name: "OpenJoystickDriverGameControllerProbe",
      path: "Sources/OpenJoystickDriverGameControllerProbe",
      linkerSettings: [
        .linkedFramework("CoreHaptics"),
        .linkedFramework("GameController"),
      ]
    ),

    .testTarget(
      name: "OpenJoystickDriverKitTests",
      dependencies: [
        "OpenJoystickDriverKit",
        .product(name: "SwiftUSB", package: "SwiftUSB"),
      ],
      path: "Tests/OpenJoystickDriverKitTests",
      swiftSettings: [
        .unsafeFlags(["-target", testTargetTriple]),
      ],
      linkerSettings: [
        .unsafeFlags([
          "-target", testTargetTriple,
          "-Xlinker", "-rpath", "-Xlinker", "/opt/homebrew/lib",
        ]),
      ]
    ),
  ]
)
