// swift-tools-version:6.4.0
import Foundation
import PackageDescription

/// The directory that holds this manifest.
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
/// Whether `OJD_USE_LOCAL_SWIFTERKIT=1` asks for the sibling `../SwifterKit` working tree instead
/// of the pinned remote.
let useLocalSwifterKit = ProcessInfo.processInfo.environment["OJD_USE_LOCAL_SWIFTERKIT"] == "1"
/// The path of the sibling SwifterKit working tree.
let localSwifterKitPath = packageDirectory.appendingPathComponent("../SwifterKit")
  .standardizedFileURL.path
/// The SwifterKit package: the local working tree when asked for and present, else the remote.
let swifterKitDependency: Package.Dependency =
  useLocalSwifterKit && FileManager.default.fileExists(atPath: localSwifterKitPath)
  ? .package(path: localSwifterKitPath)
  : .package(url: "https://github.com/xsyetopz/SwifterKit.git", from: "0.4.1")

#if arch(arm64)
  /// The target triple of the Swift Testing targets on this host.
  let testTargetTriple = "arm64-apple-macosx14.0"
#elseif arch(x86_64)
  /// The target triple of the Swift Testing targets on this host.
  let testTargetTriple = "x86_64-apple-macosx14.0"
#else
  #error("Unsupported host architecture for Swift Testing target triple")
#endif

/// The OpenJoystickDriver package.
let package = Package(
  name: "OpenJoystickDriver",
  defaultLocalization: "en-US",
  platforms: [.macOS(.v12), .iOS(.v15)],
  // OpenJoystickDriver.xcodeproj links the libraries that its app target imports.
  products: [
    .library(name: "OpenJoystickDriverKit", targets: ["OpenJoystickDriverKit"]),
    .library(name: "OpenJoystickDriverService", targets: ["OpenJoystickDriverService"]),
    .library(name: "OpenJoystickDriverCLI", targets: ["OpenJoystickDriverCLI"]),
    .library(name: "OpenJoystickDriverPresentation", targets: ["OpenJoystickDriverPresentation"]),
    .library(name: "OpenJoystickDriverMacOSHost", targets: ["OpenJoystickDriverMacOSHost"]),
  ],
  dependencies: [
    swifterKitDependency,
    // The endpoint client of the bridge tool: a package without dependencies, for the endpoint
    // tests. See Tools/BridgeCore/Package.swift.
    .package(path: "Tools/BridgeCore"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
  ],
  targets: [
    .target(
      name: "OpenJoystickDriverKit",
      dependencies: [],
      path: "Sources/OpenJoystickDriverKit",
      resources: [.process("Resources/")]
    ),

    .target(
      name: "OpenJoystickDriverMacOSPlatform",
      dependencies: ["OpenJoystickDriverKit"],
      path: "Sources/OpenJoystickDriverMacOSPlatform",
      linkerSettings: [
        .linkedFramework("CoreGraphics"), .linkedFramework("GameController"),
        .linkedFramework("IOKit"), .linkedFramework("Security"),
        .linkedFramework("ServiceManagement"),
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
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverUSB",
        .product(name: "SwifterKit", package: "SwifterKit"),
      ],
      path: "Sources/DriverKitGenerator",
      exclude: ["Entitlements"]
    ),

    .executableTarget(
      name: "OJDRepositoryTool",
      dependencies: ["OpenJoystickDriverKit"],
      path: "Sources/OJDRepositoryTool"
    ),

    .target(
      name: "OpenJoystickDriverService",
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverMacOSPlatform", "OpenJoystickDriverUSB",
      ],
      path: "Sources/OpenJoystickDriverService",
      linkerSettings: [
        .linkedFramework("CoreBluetooth"), .linkedFramework("GameController"),
        .linkedFramework("IOBluetooth"), .linkedFramework("SystemExtensions"),
      ]
    ),

    .target(
      name: "OpenJoystickDriverCLI",
      dependencies: [
        "OpenJoystickDriverKit", .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/OpenJoystickDriverCLI"
    ),

    .target(
      name: "OpenJoystickDriverMacOSHost",
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverMacOSPlatform", "OpenJoystickDriverUSB",
        "OpenJoystickDriverService",
        "OpenJoystickDriverPresentation",
      ],
      path: "Sources/OpenJoystickDriverMacOSHost"
    ),

    .target(
      name: "OpenJoystickDriverPresentation",
      dependencies: ["OpenJoystickDriverKit"],
      path: "Sources/OpenJoystickDriverPresentation"
    ),

    .executableTarget(
      name: "OpenJoystickDriver",
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverService", "OpenJoystickDriverCLI",
        "OpenJoystickDriverPresentation", "OpenJoystickDriverMacOSHost",
      ],
      path: "Sources/OpenJoystickDriver",
      exclude: ["App/Host.entitlements", "App/Info.plist"],
      resources: [.copy("Resources")]
    ),

    .executableTarget(
      name: "OpenJoystickDriverHIDTool",
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverMacOSPlatform", "OpenJoystickDriverUSB",
      ],
      path: "Sources/OpenJoystickDriverHIDTool"
    ),

    .executableTarget(
      name: "OpenJoystickDriverGameControllerProbe",
      dependencies: ["OpenJoystickDriverKit", "OpenJoystickDriverMacOSPlatform"],
      path: "Sources/OpenJoystickDriverGameControllerProbe",
      linkerSettings: [.linkedFramework("CoreHaptics"), .linkedFramework("GameController")]
    ),

    .executableTarget(
      name: "OpenJoystickDriverGameControllerViewer",
      path: "Sources/OpenJoystickDriverGameControllerViewer",
      linkerSettings: [
        .linkedFramework("AppKit"), .linkedFramework("GameController"), .linkedFramework("SwiftUI"),
      ]
    ),

    .executableTarget(
      name: "ParserCompatibilityHarness",
      dependencies: ["OpenJoystickDriverKit", "ProtocolPacketFixtures"],
      path: "Tests/ParserCompatibilityHarness",
      swiftSettings: [.unsafeFlags(["-target", testTargetTriple])],
      linkerSettings: [.unsafeFlags(["-target", testTargetTriple])]
    ),
    .testTarget(
      name: "OpenJoystickDriverKitTests",
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverUSB", "OpenJoystickDriverTestSupport",
        "ProtocolPacketFixtures",
      ],
      path: "Tests/OpenJoystickDriverKitTests",
      resources: [
        .copy("Protocol/Catalog/SchemaRejections"), .copy("Protocol/Catalog/SDLMappingFixtures"),
        .copy("Protocol/Drivers/Nintendo/Fixtures/Wii"),
      ],
      swiftSettings: [.unsafeFlags(["-target", testTargetTriple])],
      linkerSettings: [.unsafeFlags(["-target", testTargetTriple])]
    ),
    .target(
      name: "ProtocolPacketFixtures",
      path: "Tests/ProtocolPacketFixtures",
      resources: [.copy("Switch2")],
      swiftSettings: [.unsafeFlags(["-target", testTargetTriple])],
      linkerSettings: [.unsafeFlags(["-target", testTargetTriple])]
    ),
    .testTarget(
      name: "OpenJoystickDriverUSBTests",
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverUSB", "ProtocolPacketFixtures",
        .product(name: "SwifterKit", package: "SwifterKit"),
      ],
      path: "Tests/OpenJoystickDriverUSBTests",
      swiftSettings: [.unsafeFlags(["-target", testTargetTriple])],
      linkerSettings: [.unsafeFlags(["-target", testTargetTriple])]
    ),
    .target(
      name: "OpenJoystickDriverTestSupport",
      dependencies: ["OpenJoystickDriverKit"],
      path: "Tests/OpenJoystickDriverTestSupport",
      swiftSettings: [.unsafeFlags(["-target", testTargetTriple])],
      linkerSettings: [.unsafeFlags(["-target", testTargetTriple])]
    ),
    .testTarget(
      name: "OpenJoystickDriverServiceTests",
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverService", "OpenJoystickDriverCLI",
        "OpenJoystickDriverPresentation", "OpenJoystickDriverTestSupport",
        .product(name: "BridgeCore", package: "BridgeCore"),
      ],
      path: "Tests/OpenJoystickDriverServiceTests",
      swiftSettings: [.unsafeFlags(["-target", testTargetTriple])],
      linkerSettings: [.unsafeFlags(["-target", testTargetTriple])]
    ),
    .testTarget(
      name: "OpenJoystickDriverCLITests",
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverService", "OpenJoystickDriverCLI",
        "OpenJoystickDriverTestSupport",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Tests/OpenJoystickDriverCLITests",
      exclude: ["Fixtures"],
      swiftSettings: [.unsafeFlags(["-target", testTargetTriple])],
      linkerSettings: [.unsafeFlags(["-target", testTargetTriple])]
    ),
    .testTarget(
      name: "OJDRepositoryToolTests",
      dependencies: ["OpenJoystickDriverKit", "OJDRepositoryTool"],
      path: "Tests/OJDRepositoryToolTests",
      swiftSettings: [.unsafeFlags(["-target", testTargetTriple])],
      linkerSettings: [.unsafeFlags(["-target", testTargetTriple])]
    ),
    .testTarget(
      name: "OpenJoystickDriverMacOSPlatformTests",
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverMacOSPlatform", "OpenJoystickDriverTestSupport",
      ],
      path: "Tests/OpenJoystickDriverMacOSPlatformTests",
      swiftSettings: [.unsafeFlags(["-target", testTargetTriple])],
      linkerSettings: [.unsafeFlags(["-target", testTargetTriple])]
    ),
    .testTarget(
      name: "OpenJoystickDriverPresentationTests",
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverUSB", "OpenJoystickDriverPresentation",
        "OpenJoystickDriverTestSupport",
      ],
      path: "Tests/OpenJoystickDriverPresentationTests",
      swiftSettings: [.unsafeFlags(["-target", testTargetTriple])],
      linkerSettings: [.unsafeFlags(["-target", testTargetTriple])]
    ),
  ]
)

// Warnings are errors in every target of this package. The setting is per target, unlike a global
// `-Xswiftc -warnings-as-errors`, which would also reach dependencies: swift-argument-parser 1.8.2
// uses its own deprecated `_errorLabel`.
for target in package.targets {
  target.swiftSettings = (target.swiftSettings ?? []) + [.treatAllWarnings(as: .error)]
}
