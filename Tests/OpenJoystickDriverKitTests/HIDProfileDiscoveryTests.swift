import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct HIDProfileDiscoveryTests {
  @Test
  func catalogIncludesSteamProfilesButExcludesRawUSBProfiles() {
    let identifiers = Set(
      ParserRegistry().hidProfileIdentifiers().map {
        "\($0.vendorID):\($0.productID)"
      }
    )

    #expect(identifiers.contains("10462:4354"))
    #expect(identifiers.contains("10462:4418"))
    #expect(identifiers.contains("1356:1476"))
    #expect(identifiers.contains("1406:8201"))
    #expect(!identifiers.contains("1133:49693"))
    #expect(!identifiers.contains("5426:2627"))
  }

  @Test
  func hidManagerUsesGamePadAndExactProfileMatches() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let stream = try source(
      "Sources/OpenJoystickDriverKit/HID/HIDDeviceStream.swift",
      root: root
    )
    let manager = try source(
      "Sources/OpenJoystickDriverKit/Device/DeviceManager.swift",
      root: root
    )

    #expect(stream.contains("IOHIDManagerSetDeviceMatchingMultiple"))
    #expect(stream.contains("kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad"))
    #expect(stream.contains("kIOHIDVendorIDKey: Int($0.vendorID)"))
    #expect(stream.contains("kIOHIDProductIDKey: Int($0.productID)"))
    #expect(manager.contains("registry.hidProfileIdentifiers()"))
    #expect(!stream.contains("IOHIDManagerSetDeviceMatching(manager, nil)"))
    #expect(stream.contains("[UInt32: [IOHIDDevice]]"))
    #expect(stream.contains("for device in devices"))
    #expect(stream.contains("if result == kIOReturnSuccess { return true }"))
    #expect(!stream.contains("seizedByLocation[locationID] = device\n"))
  }

  private func source(_ path: String, root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
