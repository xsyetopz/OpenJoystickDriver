import Foundation
import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit

struct VirtualControllerBackendTests {
  @Test
  func testGameControllerHIDBackendCapability() {
    let capabilities = VirtualControllerBackendCatalog.gameControllerHIDCapabilities

    #expect(capabilities.isImplemented)
    #expect(capabilities.isSystemWide)
    #expect(capabilities.notes.contains("apple-gamecontroller"))
  }
  @Test
  func testDriverKitBackendCapability() {
    let backend: any VirtualControllerBackend = DextOutputDispatcher()

    #expect(backend.backendID == .driverKitHID)
    #expect(backend.capabilities.isImplemented)
    #expect(backend.capabilities.isSystemWide)
    #expect(backend.capabilities.requiresEntitlement)
  }
  @Test
  func testCompatibilityIdentityIDs() {
    #expect(CompatibilityIdentity(rawValue: "generic-hid") == .genericHID)
    #expect(CompatibilityIdentity(rawValue: "sdl2-3") == .sdl2_3)
    #expect(CompatibilityIdentity(rawValue: "apple-gamecontroller") == .appleGameController)
    #expect(CompatibilityIdentity(rawValue: "x360-hid") == .x360HID)
    #expect(CompatibilityIdentity(rawValue: "xone-hid") == .xoneHID)

    #expect(CompatibilityIdentity(rawValue: "not-a-profile") == nil)
  }
  @Test
  func testCompatibilityProfileCatalog() {
    let generic = CompatibilityOutputProfileCatalog.profile(for: .genericHID)
    let sdl = CompatibilityOutputProfileCatalog.profile(for: .sdl2_3)
    let apple = CompatibilityOutputProfileCatalog.profile(for: .appleGameController)
    let x360 = CompatibilityOutputProfileCatalog.profile(for: .x360HID)
    let xone = CompatibilityOutputProfileCatalog.profile(for: .xoneHID)

    #expect(generic.deviceProfile.productID == 0x028E)
    #expect(sdl.deviceProfile.productID == 0x028E)
    #expect(apple.deviceProfile.productID == 0x028E)
    #expect(generic.isHardwareSpoof)
    #expect(sdl.isHardwareSpoof)
    #expect(apple.isHardwareSpoof)
    #expect(x360.isHardwareSpoof)
    #expect(x360.deviceProfile.vendorID == 0x045E)
    #expect(x360.deviceProfile.productID == 0x028E)
    #expect(x360.deviceProfile.productName == "Xbox 360 Wired Controller")
    #expect(xone.isHardwareSpoof)
    #expect(xone.deviceProfile.productID == 0x02E0)
    #expect(xone.deviceProfile.versionNumber == 0x5326)
    #expect(xone.deviceProfile.productName == "Xbox One Wireless Controller")
    #expect(xone.emitsXboxGuideReport)
  }
  @Test
  func testOJDOwnedIdentitiesUseBrowserAcceptedProfileInCompatibilityMode() throws {
    for identity in [CompatibilityIdentity.genericHID, .sdl2_3] {
      let profile = CompatibilityOutputProfileCatalog.profile(for: identity).deviceProfile
      let (format, primaryUsage) = try UserSpaceOutputDispatcher.compatibilityReportFormat(
        for: identity,
        profile: profile
      )

      #expect(profile.vendorID == 0x045E)
      #expect(profile.productID == 0x028E)
      #expect(profile.productName == "Xbox 360 Wired Controller")
      #expect(format is Xbox360SDLHIDReportFormat)
      #expect(format.inputReportPayloadSize == 20)
      #expect(primaryUsage == kHIDUsage_GD_GamePad)
    }
  }
  @Test
  func testCompatibilityIdentitiesRequestDriverKitSeizure() {
    for identity in CompatibilityIdentity.allCases {
      #expect(identity.seizesDriverKitInCompatibilityMode)
    }
  }
  @Test
  func testGenericReportDpadButtonPolicy() {
    let state = VirtualGamepadState(
      buttons: GamepadHIDDescriptor.dpadButtonBits(for: .north)
        | (1 << GamepadHIDDescriptor.ButtonBit.share.rawValue),
      hat: .north
    )

    let generic = OJDGenericGamepadFormat().buildInputReport(from: state)
    #expect((UInt16(generic[1]) & 0x88) == 0x88)
    #expect((generic[14] & 0x0F) == GamepadHIDDescriptor.Hat.north.rawValue)

    let sdl2_3 = OJDGenericGamepadFormat(includesDpadButtonBits: false)
      .buildInputReport(from: state)
    #expect((UInt16(sdl2_3[1]) & 0x78) == 0)
    #expect((UInt16(sdl2_3[1]) & 0x80) == 0x80)
    #expect((sdl2_3[14] & 0x0F) == GamepadHIDDescriptor.Hat.north.rawValue)
  }
  @Test
  func testSdlReportUsesButtonDpadAndNeutralTriggers() throws {
    let parsed = try HIDDescriptorReportFormat(descriptor: OJDSDLGamepadFormat().descriptor)
    let neutral = OJDSDLGamepadFormat().buildInputReport(from: VirtualGamepadState())
    let dpad = OJDSDLGamepadFormat().buildInputReport(
      from: VirtualGamepadState(
        buttons: GamepadHIDDescriptor.dpadButtonBits(for: .north)
          | GamepadHIDDescriptor.dpadButtonBits(for: .east),
        hat: .northEast
      )
    )
    let triggers = OJDSDLGamepadFormat().buildInputReport(
      from: VirtualGamepadState(leftTrigger: 32_767, rightTrigger: 16_384)
    )

    #expect(parsed.inputReportPayloadSize == 14)
    #expect(!OJDSDLGamepadFormat().descriptor.contains(0x39))
    #expect(OJDSDLGamepadFormat().descriptor.containsSequence([
      0x09, 0x32,  // LT/Z
      0x15, 0x00,  // Logical Minimum: 0
      0x26, 0xFF, 0x7F,
    ]))
    #expect(OJDSDLGamepadFormat().descriptor.containsSequence([
      0x09, 0x35,  // RT/Rz
      0x15, 0x00,  // Logical Minimum: 0
      0x26, 0xFF, 0x7F,
    ]))
    #expect(neutral[6] == 0x00)
    #expect(neutral[7] == 0x00)
    #expect(neutral[12] == 0x00)
    #expect(neutral[13] == 0x00)
    #expect((UInt16(dpad[1]) & 0x48) == 0x48)
    #expect(triggers[6] == 0xFF)
    #expect(triggers[7] == 0x7F)
    #expect(triggers[12] == 0x00)
    #expect(triggers[13] == 0x40)
  }
  @Test
  func testSdlRumbleOutputReportUsesVendorPayload() {
    #expect(SDLGamepadHIDDescriptor.maxOutputReportPayloadSize == 7)
    #expect(OJDSDLGamepadFormat().outputReportPayloadSize == 7)
    #expect(OJDSDLGamepadFormat().descriptor.containsSequence([
      0x06, 0x00, 0xFF,  // vendor-defined output page
      0x09, 0x01,
      0x15, 0x00,
      0x26, 0xFF, 0x00,
      0x75, 0x08,
      0x95, 0x07,
      0x91, 0x02,
    ]))
  }

  @Test

  func testUserSpaceSDLIdentityAdvertisesReportSizes() {
    let properties = UserSpaceOutputDispatcher.deviceProperties(
      profile: .openJoystickDriverSDL2_3,
      format: OJDSDLGamepadFormat(),
      identifier: DeviceIdentifier(vendorID: 13623, productID: 4112)
    )

    let inputSize = properties[kIOHIDMaxInputReportSizeKey as String] as? Int
    let outputSize = properties[kIOHIDMaxOutputReportSizeKey as String] as? Int
    #expect(inputSize == SDLGamepadHIDDescriptor.reportSize)
    #expect(outputSize == SDLGamepadHIDDescriptor.maxOutputReportPayloadSize)
  }
  @Test
  func testUserSpaceDispatcherFailsFastWithoutVirtualDeviceEntitlement() throws {
    guard !UserSpaceOutputDispatcher.hasRequiredVirtualDeviceEntitlement else { return }

    do {
      _ = try UserSpaceOutputDispatcher()
      Issue.record("UserSpaceOutputDispatcher should require the virtual HID entitlement")
    } catch UserSpaceOutputDispatcher.CreationError.missingEntitlement(let entitlement) {
      #expect(entitlement == UserSpaceOutputDispatcher.requiredVirtualDeviceEntitlement)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func testUserSpaceDispatcherPreflightsAccessibilityAfterEntitlement() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let dispatcherURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverKit/Output/Backends/UserSpaceOutputDispatcher.swift"
    )
    let source = try String(contentsOf: dispatcherURL, encoding: .utf8)

    #expect(source.contains("missingAccessibilityPermission"))
    #expect(source.contains("PermissionManager.currentAccessibilityState() == .granted"))
    #expect(source.contains("Accessibility permission required for virtual HID device"))
  }

  @Test
  func testUserSpaceDispatcherPublishesInitialNeutralReportOnActivation() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let dispatcherURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverKit/Output/Backends/UserSpaceOutputDispatcher.swift"
    )
    let source = try String(contentsOf: dispatcherURL, encoding: .utf8)

    #expect(source.contains("sendInitialInputReport(to: dev)"))
    #expect(source.contains("format.buildInputReport(from: VirtualGamepadState())"))
    #expect(source.contains("IOHIDUserDeviceHandleReportWithTimeStamp("))
    #expect(source.contains("status = \"on (initial neutral report failed:"))
  }

  @Test
  func testUserSpaceGetReportReturnsCurrentStateWithoutDuplicatingReportID() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let dispatcherURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverKit/Output/Backends/UserSpaceOutputDispatcher.swift"
    )
    let source = try String(contentsOf: dispatcherURL, encoding: .utf8)
    guard
      let getReportStart = source.range(of: "IOHIDUserDeviceRegisterGetReportBlock(dev)"),
      let getReportEnd = source.range(
        of: "if let onRumbleCommand",
        range: getReportStart.upperBound..<source.endIndex
      )
    else {
      Issue.record("Could not locate user-space GetReport block")
      return
    }
    let getReportSource = String(source[getReportStart.lowerBound..<getReportEnd.lowerBound])

    #expect(getReportSource.contains("stateBox.currentReport(format: self.format)"))
    #expect(
      getReportSource.contains(
        "Self.payloadBytes(for: currentReport, reportID: expectedReportID)"
      )
    )
    #expect(!getReportSource.contains("VirtualGamepadState()"))
  }

  @Test
  func testUserSpaceStatusPublishesDispatchAndGetReportTelemetry() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let dispatcherURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverKit/Output/Backends/UserSpaceOutputDispatcher.swift"
    )
    let source = try String(contentsOf: dispatcherURL, encoding: .utf8)

    #expect(source.contains("recordInputDispatchTelemetry("))
    #expect(source.contains("eventCount: events.count"))
    #expect(source.contains("recordGetReportTelemetry(result: kIOReturnSuccess)"))
    #expect(source.contains("dispatches="))
    #expect(source.contains("nonEmpty="))
    #expect(source.contains("events="))
    #expect(source.contains("writes="))
    #expect(source.contains("getReports="))
    #expect(source.contains("lastWrite=0x"))
    #expect(source.contains("lastGet=0x"))
  }

  @Test
  func testXbox360FormatDefaultsToJoystickPrimaryUsage() {
    #expect(
      UserSpaceOutputDispatcher.defaultPrimaryUsage(for: Xbox360MacHIDReportFormat())
        == kHIDUsage_GD_Joystick
    )
  }
  @Test
  func testXbox360GamePadFormatDefaultsToGamePadPrimaryUsage() {
    #expect(UserSpaceOutputDispatcher.defaultPrimaryUsage(
        for: Xbox360MacHIDReportFormat(topLevelUsage: UInt8(kHIDUsage_GD_GamePad))
      ) == kHIDUsage_GD_GamePad)
  }
  @Test
  func testAppleGameControllerIdentityUsesAcceptedXbox360IdentityWithSDLPacketShape() throws {
    let profile = CompatibilityOutputProfileCatalog.profile(for: .appleGameController).deviceProfile
    let (format, primaryUsage) = try UserSpaceOutputDispatcher.compatibilityReportFormat(
      for: .appleGameController,
      profile: profile
    )

    #expect(profile.productID == 0x028E)
    #expect(format is Xbox360SDLHIDReportFormat)
    #expect(format.inputReportID == nil)
    #expect(format.inputReportPayloadSize == 20)
    #expect(primaryUsage == kHIDUsage_GD_GamePad)
  }
  @Test
  func testXbox360CompatibilityIdentityUsesSDLMappingFormat() throws {
    let profile = CompatibilityOutputProfileCatalog.profile(for: .x360HID).deviceProfile
    let (format, primaryUsage) = try UserSpaceOutputDispatcher.compatibilityReportFormat(
      for: .x360HID,
      profile: profile
    )

    #expect(format is Xbox360SDLHIDReportFormat)
    #expect(primaryUsage == nil)
  }
  @Test
  func testXboxOneCompatibilityFormatDeclaresRumbleOutputSize() throws {
    let format = try HIDDescriptorReportFormat(
      descriptor: XboxOneBluetoothHIDDescriptor.descriptor,
      outputReportID: VirtualRumbleOutputReportParser.xboxOneReportID,
      outputReportPayloadSize: VirtualRumbleOutputReportParser.xboxOneReportPayloadSize
    )

    #expect(format.inputReportID == 1)
    #expect(format.outputReportID == VirtualRumbleOutputReportParser.xboxOneReportID)
    #expect(
      format.outputReportPayloadSize == VirtualRumbleOutputReportParser.xboxOneReportPayloadSize
    )
  }
  @Test
  func testXboxOneCompatibilitySwapsCenterButtonsForSafariOrder() throws {
    let profile = CompatibilityOutputProfileCatalog.profile(for: .xoneHID).deviceProfile
    let (format, _) = try UserSpaceOutputDispatcher.compatibilityReportFormat(
      for: .xoneHID,
      profile: profile
    )

    let leftStick = format.buildInputReport(
      from: VirtualGamepadState(
        buttons: 1 << GamepadHIDDescriptor.ButtonBit.leftStick.rawValue
      )
    )
    let rightStick = format.buildInputReport(
      from: VirtualGamepadState(
        buttons: 1 << GamepadHIDDescriptor.ButtonBit.rightStick.rawValue
      )
    )
    let menu = format.buildInputReport(
      from: VirtualGamepadState(buttons: 1 << GamepadHIDDescriptor.ButtonBit.start.rawValue)
    )
    let view = format.buildInputReport(
      from: VirtualGamepadState(buttons: 1 << GamepadHIDDescriptor.ButtonBit.back.rawValue)
    )

    #expect(leftStick[15] == 0x01)
    #expect(rightStick[15] == 0x02)
    #expect(menu[14] == 0x80)
    #expect(view[14] == 0x40)
  }
  @Test
  func testXboxGIPCompatibilityFormatAdvertisesFullOutputSize() throws {
    let format = try HIDDescriptorReportFormat(
      descriptor: XboxOneBluetoothHIDDescriptor.descriptor,
      outputReportID: VirtualRumbleOutputReportParser.xboxGIPReportID,
      outputReportPayloadSize:
        VirtualRumbleOutputReportParser.xboxGIPReportPayloadSizeWithoutReportID
    )
    let properties = UserSpaceOutputDispatcher.deviceProperties(
      profile: .xboxOneS,
      format: format,
      identifier: DeviceIdentifier(vendorID: 13623, productID: 4112)
    )

    let outputSize = properties[kIOHIDMaxOutputReportSizeKey as String] as? Int
    #expect(outputSize == 13)
  }
  @Test
  func testFixedCompatibilityReportHasNoHatAxis() throws {
    let parsed = try HIDDescriptorReportFormat(descriptor: OJDSDLGamepadFormat().descriptor)
    let full = OJDSDLGamepadFormat().buildInputReport(
      from: VirtualGamepadState(
        buttons: GamepadHIDDescriptor.dpadButtonBits(for: .south)
          | (1 << GamepadHIDDescriptor.ButtonBit.leftStick.rawValue)
          | (1 << GamepadHIDDescriptor.ButtonBit.rightStick.rawValue)
          | (1 << GamepadHIDDescriptor.ButtonBit.start.rawValue)
          | (1 << GamepadHIDDescriptor.ButtonBit.back.rawValue)
          | (1 << GamepadHIDDescriptor.ButtonBit.guide.rawValue)
          | (1 << GamepadHIDDescriptor.ButtonBit.share.rawValue),
        leftTrigger: 32_767,
        rightTrigger: 32_767,
        hat: .south
      )
    )

    #expect(parsed.inputReportPayloadSize == 14)
    #expect(!OJDSDLGamepadFormat().descriptor.contains(0x39))
    #expect(full[1] == 0x97)
    #expect(full[6] == 0xFF)
    #expect(full[7] == 0x7F)
    #expect(full[12] == 0xFF)
    #expect(full[13] == 0x7F)
  }

  @Test
  func testCompatibilityFormatsReturnFullyNeutralReportsAfterRelease() throws {
    let generic = OJDGenericGamepadFormat().buildInputReport(from: VirtualGamepadState())
    let sdl = OJDSDLGamepadFormat().buildInputReport(from: VirtualGamepadState())
    let apple = Xbox360MacHIDReportFormat(topLevelUsage: UInt8(kHIDUsage_GD_GamePad))
      .buildInputReport(from: VirtualGamepadState())
    let x360 = Xbox360SDLHIDReportFormat().buildInputReport(from: VirtualGamepadState())
    let xone = try HIDDescriptorReportFormat(descriptor: XboxOneBluetoothHIDDescriptor.descriptor)
      .buildInputReport(from: VirtualGamepadState())

    #expect(generic == [UInt8](repeating: 0, count: generic.count))
    #expect(sdl == [UInt8](repeating: 0, count: sdl.count))
    #expect(Array(apple.dropFirst(2)) == [UInt8](repeating: 0, count: apple.count - 2))
    #expect(Array(x360.prefix(2)) == [0x00, 0x14])
    #expect(Array(x360.dropFirst(2)) == [UInt8](repeating: 0, count: x360.count - 2))
    #expect(xone[0] == 1)
    #expect(xone[13] == 0x00)
    #expect(xone[14] == 0x00)
    #expect(xone[15] == 0x00)
  }

}

private extension Array where Element: Equatable {
  func containsSequence(_ sequence: [Element]) -> Bool {
    guard !sequence.isEmpty, sequence.count <= count else { return false }
    return indices.dropLast(sequence.count - 1).contains { index in
      self[index..<(index + sequence.count)].elementsEqual(sequence)
    }
  }
}
