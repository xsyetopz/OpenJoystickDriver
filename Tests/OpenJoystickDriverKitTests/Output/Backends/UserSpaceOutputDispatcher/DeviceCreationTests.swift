import Foundation
import IOKit
import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit

struct UserSpaceDeviceCreationTests {
  @Test
  func failedCreateIsExplainedByMissingPermissionsOrReportedAsCreateFailure() {
    let classify = UserSpaceOutputDispatcher.creationFailure
    #expect(
      "\(classify(.denied, .granted))"
        == "\(UserSpaceOutputDispatcher.CreationError.inputMonitoringDenied)"
    )
    #expect(
      "\(classify(.granted, .unknown))"
        == "\(UserSpaceOutputDispatcher.CreationError.accessibilityDenied)"
    )
    #expect(
      "\(classify(.granted, .granted))" == "\(UserSpaceOutputDispatcher.CreationError.createFailed)"
    )
  }

  @Test
  func retryPolicyPermitsOneAttemptPerDelayWindow() {
    var policy = UserSpaceDeviceCreationRetryPolicy(delayNanoseconds: 5)

    #expect(policy.permitsAttempt(at: 100))
    policy.recordFailure(at: 100)

    #expect(!policy.permitsAttempt(at: 100))
    #expect(!policy.permitsAttempt(at: 104))
    #expect(policy.permitsAttempt(at: 105))
  }

  @Test
  func retryPolicyClampsOverflowAtMaximumTimestamp() {
    var policy = UserSpaceDeviceCreationRetryPolicy(delayNanoseconds: 5)

    policy.recordFailure(at: UInt64.max - 2)

    #expect(policy.nextAttemptNanoseconds == UInt64.max)
    #expect(!policy.permitsAttempt(at: UInt64.max - 1))
    #expect(policy.permitsAttempt(at: UInt64.max))
  }

  @Test(arguments: [
    (VirtualDeviceProfile.xboxOneS, kIOHIDTransportBluetoothValue),
    (VirtualDeviceProfile.openJoystickDriverGenericHID, kIOHIDTransportUSBValue),
  ])
  func ioHIDTransportValueMatchesIdentity(_ profile: VirtualDeviceProfile, _ expected: String) {
    #expect(UserSpaceOutputDispatcher.ioHIDTransportValue(for: profile) == expected)
    let properties = UserSpaceOutputDispatcher.deviceProperties(
      profile: profile,
      format: OJDGenericGamepadFormat(),
      identifier: DeviceIdentifier(vendorID: 1, productID: 1)
    )
    #expect(properties[kIOHIDTransportKey as String] as? String == expected)
  }

  @Test
  func creationIsDeferredUntilActivation() {
    #expect(UserSpaceOutputDispatcher.deviceCreationOptions == IOOptionBits(1 << 0))
  }

  /// Consumers key mappings on these exact values (SDL's GUID includes the version), so each
  /// profile's published identity is pinned literally rather than read back from the profile.
  @Test(arguments: [
    (
      VirtualHIDProfileID.xboxOneSBluetooth, 0x045E, 0x02FD, 0x0000, "Xbox Wireless Controller",
      "Microsoft", "Bluetooth", UInt64(0x8C79_2AA2_4C28_57BD), Int?(9)
    ),
    (
      VirtualHIDProfileID.generic, 0x1209, 0x4A4F, 0x0408, "OpenJoystickDriver Generic HID Gamepad",
      "OpenJoystickDriver", "USB", UInt64(0x1ECB_8E98_9A22_47A8), Int?.none
    ),
  ])
  func publishedIdentityIsPinnedPerProfile(
    _ profileID: VirtualHIDProfileID,
    _ vendorID: Int,
    _ productID: Int,
    _ version: Int,
    _ product: String,
    _ manufacturer: String,
    _ transport: String,
    _ descriptorFNV1a: UInt64,
    _ maxOutputReportSize: Int?
  ) throws {
    let profile = try profileID.makeProfile()
    let properties = UserSpaceOutputDispatcher.deviceProperties(
      profile: profile.identity,
      format: profile.reportFormat,
      identifier: DeviceIdentifier(vendorID: 1, productID: 2)
    )
    #expect(properties[kIOHIDVendorIDKey as String] as? Int == vendorID)
    #expect(properties[kIOHIDProductIDKey as String] as? Int == productID)
    #expect(properties[kIOHIDVersionNumberKey as String] as? Int == version)
    #expect(properties[kIOHIDProductKey as String] as? String == product)
    #expect(properties[kIOHIDManufacturerKey as String] as? String == manufacturer)
    #expect(properties[kIOHIDTransportKey as String] as? String == transport)
    let descriptor = try #require(properties[kIOHIDReportDescriptorKey as String] as? Data)
    let hash = descriptor.reduce(UInt64(0xCBF2_9CE4_8422_2325)) {
      ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3
    }
    #expect(hash == descriptorFNV1a)
    // The generic profile is input-only, so it publishes no output report size.
    #expect(properties[kIOHIDMaxOutputReportSizeKey as String] as? Int == maxOutputReportSize)
  }

  /// A custom persona replaces the identity strings and IDs of the published device, and keeps the
  /// built-in descriptor, the transport, and the virtual LocationID.
  @Test(arguments: VirtualHIDProfileID.allCases)
  func personaIdentityIsPublishedOverTheBuiltInDescriptor(_ profileID: VirtualHIDProfileID) throws {
    let builtIn = try profileID.makeProfile()
    let persona = VirtualPersona.Identity(
      vendorID: 0x1234,
      productID: 0x5678,
      versionNumber: nil,
      productName: "Custom Pad",
      manufacturer: "Custom Maker",
      glyphFamily: .xbox
    )
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 3)
    func properties(_ profile: VirtualDeviceProfile) -> [String: Any] {
      UserSpaceOutputDispatcher.deviceProperties(
        profile: profile,
        format: builtIn.reportFormat,
        identifier: identifier
      )
    }
    let plain = properties(builtIn.identity)
    let custom = properties(builtIn.identity.applying(persona))

    #expect(custom[kIOHIDVendorIDKey as String] as? Int == 0x1234)
    #expect(custom[kIOHIDProductIDKey as String] as? Int == 0x5678)
    #expect(custom[kIOHIDProductKey as String] as? String == "Custom Pad")
    #expect(custom[kIOHIDManufacturerKey as String] as? String == "Custom Maker")
    #expect(custom[kIOHIDVersionNumberKey as String] as? Int == builtIn.identity.versionNumber)
    #expect(
      custom[kIOHIDTransportKey as String] as? String == plain[kIOHIDTransportKey as String]
        as? String
    )
    #expect(
      custom[kIOHIDReportDescriptorKey as String] as? Data
        == plain[kIOHIDReportDescriptorKey as String] as? Data
    )
    #expect(
      custom[kIOHIDLocationIDKey as String] as? Int == plain[kIOHIDLocationIDKey as String] as? Int
    )
  }

  @Test(arguments: VirtualHIDProfileID.allCases)
  func publishedIdentityMatchesTheProfileForEveryProductionProfile(
    _ profileID: VirtualHIDProfileID
  ) throws {
    let profile = try profileID.makeProfile()
    let identity = profile.identity
    let format = profile.reportFormat
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 3)

    let properties = UserSpaceOutputDispatcher.deviceProperties(
      profile: identity,
      format: format,
      identifier: identifier
    )

    #expect(properties[kIOHIDVendorIDKey as String] as? Int == Int(identity.vendorID))
    #expect(properties[kIOHIDProductIDKey as String] as? Int == Int(identity.productID))
    #expect(properties[kIOHIDVersionNumberKey as String] as? Int == identity.versionNumber)
    #expect(properties[kIOHIDProductKey as String] as? String == identity.productName)
    #expect(properties[kIOHIDManufacturerKey as String] as? String == identity.manufacturer)
    #expect(
      properties[kIOHIDTransportKey as String] as? String
        == UserSpaceOutputDispatcher.ioHIDTransportValue(for: identity)
    )
    #expect(
      properties[kIOHIDSerialNumberKey as String] as? String
        == UserSpaceVirtualDeviceConstants.serialNumber(for: identifier)
    )
    #expect(
      properties[kIOHIDLocationIDKey as String] as? Int64
        == Int64(UserSpaceVirtualDeviceConstants.locationID(for: identifier))
    )
    #expect(properties[kIOHIDPrimaryUsagePageKey as String] as? Int == Int(kHIDPage_GenericDesktop))
    #expect(properties[kIOHIDPrimaryUsageKey as String] as? Int == Int(kHIDUsage_GD_GamePad))
    let pairs = try #require(properties[kIOHIDDeviceUsagePairsKey as String] as? [[String: Int]])
    #expect(
      pairs == [
        [
          kIOHIDDeviceUsagePageKey as String: Int(kHIDPage_GenericDesktop),
          kIOHIDDeviceUsageKey as String: Int(kHIDUsage_GD_GamePad),
        ]
      ]
    )
    #expect(
      properties[kIOHIDMaxInputReportSizeKey as String] as? Int
        == UserSpaceOutputDispatcher.reportBufferSize(
          payloadSize: format.inputReportPayloadSize,
          reportID: format.inputReportID
        )
    )
    if let outputSize = format.outputReportPayloadSize {
      #expect(
        properties[kIOHIDMaxOutputReportSizeKey as String] as? Int
          == UserSpaceOutputDispatcher.reportBufferSize(
            payloadSize: outputSize,
            reportID: format.outputReportID
          )
      )
    } else {
      #expect(properties[kIOHIDMaxOutputReportSizeKey as String] == nil)
    }
    #expect(properties[kIOHIDReportDescriptorKey as String] as? Data == Data(format.descriptor))
  }

  @Test(arguments: VirtualHIDProfileID.allCases)
  func publishedIdentityIsByteIdenticalAcrossCallsForTheSameIdentifier(
    _ profileID: VirtualHIDProfileID
  ) throws {
    let profile = try profileID.makeProfile()
    let identifier = DeviceIdentifier(vendorID: 7, productID: 9, locationID: 11)

    let first = UserSpaceOutputDispatcher.deviceProperties(
      profile: profile.identity,
      format: profile.reportFormat,
      identifier: identifier
    )
    let second = UserSpaceOutputDispatcher.deviceProperties(
      profile: profile.identity,
      format: profile.reportFormat,
      identifier: identifier
    )

    #expect(Self.samePublishedProperties(first, second))
  }

  @Test(arguments: VirtualHIDProfileID.allCases)
  func differentIdentifiersDifferOnlyInSerialAndLocation(_ profileID: VirtualHIDProfileID) throws {
    let profile = try profileID.makeProfile()
    let first = DeviceIdentifier(vendorID: 7, productID: 9, locationID: 11)
    let second = DeviceIdentifier(vendorID: 7, productID: 9, locationID: 12)

    var firstProperties = UserSpaceOutputDispatcher.deviceProperties(
      profile: profile.identity,
      format: profile.reportFormat,
      identifier: first
    )
    var secondProperties = UserSpaceOutputDispatcher.deviceProperties(
      profile: profile.identity,
      format: profile.reportFormat,
      identifier: second
    )

    #expect(firstProperties[kIOHIDSerialNumberKey as String] is String)
    #expect(
      firstProperties[kIOHIDSerialNumberKey as String] as? String != secondProperties[
        kIOHIDSerialNumberKey as String
      ] as? String
    )
    #expect(
      firstProperties[kIOHIDLocationIDKey as String] as? Int64 != secondProperties[
        kIOHIDLocationIDKey as String
      ] as? Int64
    )

    for key in [kIOHIDSerialNumberKey as String, kIOHIDLocationIDKey as String] {
      firstProperties.removeValue(forKey: key)
      secondProperties.removeValue(forKey: key)
    }
    #expect(Self.samePublishedProperties(firstProperties, secondProperties))
  }

  private static func samePublishedProperties(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
    Set(lhs.keys) == Set(rhs.keys)
      && lhs.allSatisfy { key, value in (value as AnyObject).isEqual(rhs[key]) }
  }
}
