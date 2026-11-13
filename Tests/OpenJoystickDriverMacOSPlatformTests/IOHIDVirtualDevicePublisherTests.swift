import Foundation
import IOKit
import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverMacOSPlatform

struct IOHIDVirtualDevicePublisherTests {
  private static func identity(of identifier: LogicalControllerID) -> VirtualDeviceIdentity {
    var registry = VirtualIdentityRegistry()
    return registry.reserve(identifier)
  }

  @Test
  func failedCreateIsExplainedByMissingPermissionsOrReportedAsCreateFailure() {
    let classify = IOHIDVirtualDevicePublisher.creationFailure
    #expect(
      "\(classify(.denied, .granted))"
        == "\(UserSpaceOutputDispatcher.CreationError.inputReadDenied)"
    )
    #expect(
      "\(classify(.granted, .unknown))"
        == "\(UserSpaceOutputDispatcher.CreationError.inputInjectDenied)"
    )
    #expect(
      "\(classify(.granted, .granted))" == "\(UserSpaceOutputDispatcher.CreationError.createFailed)"
    )
  }

  @Test
  func nativeErrorsPreserveFailureClassification() {
    #expect(
      IOHIDVirtualDeviceBackend.ioKitError(VirtualHostReportError.unsupported)
        == kIOReturnUnsupported
    )
    #expect(
      IOHIDVirtualDeviceBackend.ioKitError(VirtualHostReportError.malformed)
        == kIOReturnBadArgument
    )
    #expect(
      IOHIDVirtualDeviceBackend.ioKitError(VirtualHostReportError.tooLarge)
        == kIOReturnMessageTooLarge
    )
    #expect(
      IOHIDVirtualDeviceBackend.ioKitError(VirtualHostReportError.closed) == kIOReturnNotOpen
    )
  }

  @Test
  func sdlCompatibleIdentityAdvertisesNumberedReportSizes() {
    let format = XboxOneGIPHIDReportFormat()
    let properties = IOHIDVirtualDevicePublisher.deviceProperties(
      profile: .sdlCompatible,
      format: format,
      identity: Self.identity(of: LogicalControllerID(vendorID: 13623, productID: 4112))
    )

    let inputSize = properties[kIOHIDMaxInputReportSizeKey as String] as? Int
    let outputSize = properties[kIOHIDMaxOutputReportSizeKey as String] as? Int
    #expect(inputSize == format.inputReportPayloadSize + 1)
    #expect(outputSize == ConsumerOutputCodec.xboxOneReportPayloadSize + 1)
  }

  @Test
  func propertiesPreserveDescriptorAndIdentity() {
    let format = XboxOneGIPHIDReportFormat()
    let profile = VirtualDeviceProfile.sdlCompatible
    let properties = IOHIDVirtualDevicePublisher.deviceProperties(
      profile: profile,
      format: format,
      identity: Self.identity(of: LogicalControllerID(vendorID: 13623, productID: 4112))
    )

    #expect(properties[kIOHIDReportDescriptorKey as String] as? Data == Data(format.descriptor))
    #expect(properties[kIOHIDVendorIDKey as String] as? Int == Int(profile.vendorID))
    #expect(properties[kIOHIDProductIDKey as String] as? Int == Int(profile.productID))
    #expect(properties[kIOHIDVersionNumberKey as String] as? Int == profile.versionNumber)
    #expect(profile.versionNumber == 0)
  }

  @Test
  func publisherFailsFastWithoutVirtualDeviceEntitlement() {
    guard
      !IOHIDVirtualDevicePublisher.hasEntitlement(
        IOHIDVirtualDevicePublisher.requiredVirtualDeviceEntitlement
      )
    else { return }

    do {
      _ = try IOHIDVirtualDevicePublisher()
      Issue.record("the publisher should require the virtual HID entitlement")
    } catch UserSpaceOutputDispatcher.CreationError.missingEntitlement(let entitlement) {
      #expect(entitlement == IOHIDVirtualDevicePublisher.requiredVirtualDeviceEntitlement)
    } catch { Issue.record("Unexpected error: \(error)") }
  }

  @Test(arguments: [
    (VirtualDeviceProfile.sdlCompatible, kIOHIDTransportUSBValue),
    (VirtualDeviceProfile.generic, kIOHIDTransportUSBValue),
  ])
  func ioHIDTransportValueMatchesIdentity(_ profile: VirtualDeviceProfile, _ expected: String) {
    #expect(IOHIDVirtualDevicePublisher.ioHIDTransportValue(for: profile) == expected)
    let properties = IOHIDVirtualDevicePublisher.deviceProperties(
      profile: profile,
      format: OJDGenericGamepadFormat(),
      identity: Self.identity(of: LogicalControllerID(vendorID: 1, productID: 1))
    )
    #expect(properties[kIOHIDTransportKey as String] as? String == expected)
  }

  @Test
  func creationIsDeferredUntilActivation() {
    #expect(IOHIDVirtualDevicePublisher.deviceCreationOptions == IOOptionBits(1 << 0))
  }

  /// Consumers key mappings on these exact values (SDL's GUID includes the version), so each
  /// profile's published identity is pinned literally rather than read back from the profile.
  @Test(arguments: [
    (
      VirtualHIDProfileID.sdlCompatible, 0x045E, 0x0B0C, 0x0000, "Xbox Adaptive Controller",
      "Microsoft", "USB", UInt64(0x48E9_971C_3CA8_EDB6), Int?(13)
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
    let profile = profileID.makeProfile()
    let properties = IOHIDVirtualDevicePublisher.deviceProperties(
      profile: profile.identity,
      format: profile.reportFormat,
      identity: Self.identity(of: LogicalControllerID(vendorID: 1, productID: 2))
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
    #expect(
      hash == descriptorFNV1a,
      "descriptor FNV-1a is 0x\(String(hash, radix: 16, uppercase: true))"
    )
    // The generic profile is input-only, so it publishes no output report size.
    #expect(properties[kIOHIDMaxOutputReportSizeKey as String] as? Int == maxOutputReportSize)
  }

  /// A custom persona replaces the identity strings and IDs of the published device, and keeps the
  /// built-in descriptor, the transport, and the virtual LocationID.
  @Test(arguments: VirtualHIDProfileID.allCases)
  func personaIdentityPublishedOverBuiltInDescriptor(_ profileID: VirtualHIDProfileID) {
    let builtIn = profileID.makeProfile()
    let persona = VirtualPersona.Identity(
      vendorID: 0x1234,
      productID: 0x5678,
      versionNumber: nil,
      productName: "Custom Pad",
      manufacturer: "Custom Maker",
      glyphFamily: .xbox
    )
    let identifier = LogicalControllerID(vendorID: 1, productID: 2, locationID: 3)
    func properties(_ profile: VirtualDeviceProfile) -> [String: Any] {
      IOHIDVirtualDevicePublisher.deviceProperties(
        profile: profile,
        format: builtIn.reportFormat,
        identity: Self.identity(of: identifier)
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
  func publishedIdentityMatchesProfileForEveryProductionProfile(
    _ profileID: VirtualHIDProfileID
  ) throws {
    let profile = profileID.makeProfile()
    let identity = profile.identity
    let format = profile.reportFormat
    let identifier = LogicalControllerID(vendorID: 1, productID: 2, locationID: 3)

    let properties = IOHIDVirtualDevicePublisher.deviceProperties(
      profile: identity,
      format: format,
      identity: Self.identity(of: identifier)
    )

    #expect(properties[kIOHIDVendorIDKey as String] as? Int == Int(identity.vendorID))
    #expect(properties[kIOHIDProductIDKey as String] as? Int == Int(identity.productID))
    #expect(properties[kIOHIDVersionNumberKey as String] as? Int == identity.versionNumber)
    #expect(properties[kIOHIDProductKey as String] as? String == identity.productName)
    #expect(properties[kIOHIDManufacturerKey as String] as? String == identity.manufacturer)
    #expect(
      properties[kIOHIDTransportKey as String] as? String
        == IOHIDVirtualDevicePublisher.ioHIDTransportValue(for: identity)
    )
    #expect(
      properties[kIOHIDSerialNumberKey as String] as? String
        == Self.identity(of: identifier).serialNumber
    )
    #expect(
      properties[kIOHIDLocationIDKey as String] as? Int64
        == Int64(Self.identity(of: identifier).locationID)
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
        == IOHIDVirtualDevicePublisher.reportBufferSize(
          payloadSize: format.inputReportPayloadSize,
          reportID: format.inputReportID
        )
    )
    if let outputSize = format.outputReportPayloadSize {
      #expect(
        properties[kIOHIDMaxOutputReportSizeKey as String] as? Int
          == IOHIDVirtualDevicePublisher.reportBufferSize(
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
  func publishedIdentityIsByteIdenticalAcrossCallsForSameIdentifier(
    _ profileID: VirtualHIDProfileID
  ) {
    let profile = profileID.makeProfile()
    let identifier = LogicalControllerID(vendorID: 7, productID: 9, locationID: 11)

    let first = IOHIDVirtualDevicePublisher.deviceProperties(
      profile: profile.identity,
      format: profile.reportFormat,
      identity: Self.identity(of: identifier)
    )
    let second = IOHIDVirtualDevicePublisher.deviceProperties(
      profile: profile.identity,
      format: profile.reportFormat,
      identity: Self.identity(of: identifier)
    )

    #expect(Self.samePublishedProperties(first, second))
  }

  @Test(arguments: VirtualHIDProfileID.allCases)
  func differentIdentifiersDifferOnlyInSerialAndLocation(_ profileID: VirtualHIDProfileID) {
    let profile = profileID.makeProfile()
    let first = LogicalControllerID(vendorID: 7, productID: 9, locationID: 11)
    let second = LogicalControllerID(vendorID: 7, productID: 9, locationID: 12)

    var firstProperties = IOHIDVirtualDevicePublisher.deviceProperties(
      profile: profile.identity,
      format: profile.reportFormat,
      identity: Self.identity(of: first)
    )
    var secondProperties = IOHIDVirtualDevicePublisher.deviceProperties(
      profile: profile.identity,
      format: profile.reportFormat,
      identity: Self.identity(of: second)
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
