// swift-tools-version: 6.4
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
  : .package(url: "https://github.com/xsyetopz/SwifterKit.git", from: "0.5.1")

/// The OpenJoystickDriver package.
let package = Package(
  name: "OpenJoystickDriver",
  defaultLocalization: "en-US",
  platforms: [.macOS(.v13), .iOS(.v15)],
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
      path: "Tests/ParserCompatibilityHarness"
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
        .copy("Protocol/Drivers/Generic/Fixtures/Ultimate2C"),
      ]
    ),
    .target(
      name: "ProtocolPacketFixtures",
      path: "Tests/ProtocolPacketFixtures",
      resources: [.copy("Switch2")]
    ),
    .testTarget(
      name: "OpenJoystickDriverUSBTests",
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverUSB", "ProtocolPacketFixtures",
        .product(name: "SwifterKit", package: "SwifterKit"),
      ],
      path: "Tests/OpenJoystickDriverUSBTests"
    ),
    .target(
      name: "OpenJoystickDriverTestSupport",
      dependencies: ["OpenJoystickDriverKit"],
      path: "Tests/OpenJoystickDriverTestSupport"
    ),
    .testTarget(
      name: "OpenJoystickDriverServiceTests",
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverService", "OpenJoystickDriverCLI",
        "OpenJoystickDriverPresentation", "OpenJoystickDriverTestSupport",
        .product(name: "BridgeCore", package: "BridgeCore"),
      ],
      path: "Tests/OpenJoystickDriverServiceTests"
    ),
    .testTarget(
      name: "OpenJoystickDriverCLITests",
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverService", "OpenJoystickDriverCLI",
        "OpenJoystickDriverTestSupport",
        // `ojd generate` starts this executable as its helper process.
        "OpenJoystickDriver",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Tests/OpenJoystickDriverCLITests",
      exclude: ["Fixtures"]
    ),
    .testTarget(
      name: "OJDRepositoryToolTests",
      dependencies: [
        "OpenJoystickDriverKit", "OJDRepositoryTool", "OpenJoystickDriverTestSupport",
      ],
      path: "Tests/OJDRepositoryToolTests"
    ),
    .testTarget(
      name: "OpenJoystickDriverMacOSPlatformTests",
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverMacOSPlatform", "OpenJoystickDriverTestSupport",
      ],
      path: "Tests/OpenJoystickDriverMacOSPlatformTests"
    ),
    .testTarget(
      name: "OpenJoystickDriverPresentationTests",
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverUSB", "OpenJoystickDriverPresentation",
        "OpenJoystickDriverTestSupport",
      ],
      path: "Tests/OpenJoystickDriverPresentationTests"
    ),
  ]
)

// Swift 6, the upcoming features, strict memory safety, and warnings as errors, for every target.
// Warnings are errors per target, unlike a global `-Xswiftc -warnings-as-errors`, which would also
// reach dependencies: swift-argument-parser 1.8.2 uses its own deprecated `_errorLabel`. The
// `just guard` check (Scripts/Quality/swift_guard.py) keeps these settings on every target.
package.swiftLanguageModes = [.v6]
for target in package.targets where ![.system, .binary, .plugin].contains(target.type) {
  target.swiftSettings =
    (target.swiftSettings ?? []) + [
      .enableUpcomingFeature("ExistentialAny"),
      .enableUpcomingFeature("InternalImportsByDefault"),
      .enableUpcomingFeature("MemberImportVisibility"),
      .enableUpcomingFeature("InferIsolatedConformances"),
      .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
      .enableUpcomingFeature("ImmutableWeakCaptures"),
      .strictMemorySafety(),
      .treatAllWarnings(as: .error),
    ]
}

// C++20, and C++ interop for every Swift target, since a target that imports a C++ module, even
// through another target, needs it.
package.cxxLanguageStandard = .cxx20
for target in package.targets where [.regular, .executable, .test].contains(target.type) {
  target.swiftSettings = (target.swiftSettings ?? []) + [.interoperabilityMode(.Cxx)]
}
