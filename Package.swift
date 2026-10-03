// swift-tools-version:6.3.0
import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
// OJD_USE_LOCAL_SWIFTERKIT=1 builds the sibling ../SwifterKit working tree instead of the pinned
// remote.
let useLocalSwifterKit = ProcessInfo.processInfo.environment["OJD_USE_LOCAL_SWIFTERKIT"] == "1"
let localSwifterKitPath = packageDirectory.appendingPathComponent("../SwifterKit")
  .standardizedFileURL.path
let swifterKitDependency: Package.Dependency =
  useLocalSwifterKit && FileManager.default.fileExists(atPath: localSwifterKitPath)
  ? .package(path: localSwifterKitPath)
  : .package(url: "https://github.com/xsyetopz/SwifterKit.git", from: "0.3.0")

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
  platforms: [.macOS(.v12), .iOS(.v15)],
  // OpenJoystickDriver.xcodeproj links the libraries that its app target imports.
  products: [
    .library(name: "OpenJoystickDriverKit", targets: ["OpenJoystickDriverKit"]),
    .library(name: "OpenJoystickDriverService", targets: ["OpenJoystickDriverService"]),
    .library(name: "OpenJoystickDriverCLI", targets: ["OpenJoystickDriverCLI"]),
    .library(name: "OpenJoystickDriverPresentation", targets: ["OpenJoystickDriverPresentation"]),
  ],
  dependencies: [
    swifterKitDependency,
    .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
  ],
  targets: [
    .target(
      name: "OpenJoystickDriverKit",
      dependencies: [],
      path: "Sources/OpenJoystickDriverKit",
      resources: [.process("Resources/")],
      linkerSettings: [.linkedFramework("GameController"), .linkedFramework("ServiceManagement")]
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

    .target(
      name: "OpenJoystickDriverService",
      dependencies: ["OpenJoystickDriverKit", "OpenJoystickDriverUSB"],
      path: "Sources/OpenJoystickDriverService",
      linkerSettings: [
        .linkedFramework("CoreBluetooth"), .linkedFramework("GameController"),
        .linkedFramework("IOBluetooth"), .linkedFramework("SystemExtensions"),
      ]
    ),

    .target(
      name: "OpenJoystickDriverCLI",
      dependencies: [
        "OpenJoystickDriverKit", "OpenJoystickDriverUSB", "OpenJoystickDriverService",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/OpenJoystickDriverCLI"
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
        "OpenJoystickDriverPresentation",
      ],
      path: "Sources/OpenJoystickDriver",
      exclude: ["App/Host.entitlements", "App/Info.plist"],
      resources: [.copy("Resources")]
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

    .executableTarget(
      name: "ParserCompatibilityHarness",
      dependencies: ["OpenJoystickDriverKit", "ProtocolPacketFixtures"],
      path: "Tests/ParserCompatibilityHarness",
      swiftSettings: [.unsafeFlags(["-target", testTargetTriple])],
      linkerSettings: [.unsafeFlags(["-target", testTargetTriple])]
    ),
    .testTarget(
      name: "OpenJoystickDriverKitTests",
      dependencies: ["OpenJoystickDriverKit", "OpenJoystickDriverUSB", "ProtocolPacketFixtures"],
      path: "Tests/OpenJoystickDriverKitTests",
      swiftSettings: [.unsafeFlags(["-target", testTargetTriple])],
      linkerSettings: [.unsafeFlags(["-target", testTargetTriple])]
    ),
    .target(
      name: "ProtocolPacketFixtures",
      path: "Tests/ProtocolPacketFixtures",
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
        "OpenJoystickDriverKit", "OpenJoystickDriverService", "OpenJoystickDriverTestSupport",
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

// Warnings are errors only in this package's app targets. A global `-Xswiftc -warnings-as-errors`
// would also reach dependencies, and swift-argument-parser 1.8.2 uses its own deprecated
// `_errorLabel`.
let warningsAsErrorsTargets: Set = [
  "OpenJoystickDriverKit", "OpenJoystickDriverUSB", "OpenJoystickDriverService",
  "OpenJoystickDriverCLI", "OpenJoystickDriverPresentation", "OpenJoystickDriver",
]
for target in package.targets where warningsAsErrorsTargets.contains(target.name) {
  target.swiftSettings = (target.swiftSettings ?? []) + [.treatAllWarnings(as: .error)]
}
