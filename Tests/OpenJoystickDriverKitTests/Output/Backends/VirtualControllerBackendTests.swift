import Dispatch
import Foundation
import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit

private final class RemovalDecisionRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var decisions: [PhysicalHIDBackendEventAdapter.RemovalDecision] = []

  func reset() { lock.withLock { decisions.removeAll() } }

  func append(_ decision: PhysicalHIDBackendEventAdapter.RemovalDecision) {
    lock.withLock { decisions.append(decision) }
  }

  func disconnectCount() -> Int { lock.withLock { decisions.filter(\.shouldEmitDisconnect).count } }
}

struct VirtualControllerBackendTests {
  @Test func testGameControllerHIDBackendCapability() {
    let capabilities = VirtualControllerBackendCatalog.gameControllerHIDCapabilities

    #expect(capabilities.isImplemented)
    #expect(capabilities.isSystemWide)
    #expect(capabilities.publishesConsumerGamepad)
    #expect(VirtualControllerBackendID.allCases.contains(.gameControllerHID))
    #expect(!capabilities.notes.isEmpty)
  }

  @Test func testCompatibilityIdentityIDs() {
    #expect(CompatibilityIdentity(rawValue: "generic-hid") == .genericHID)
    #expect(CompatibilityIdentity(rawValue: "sdl2-3") == .sdl2_3)
    #expect(CompatibilityIdentity(rawValue: "apple-gamecontroller") == .appleGameController)
    #expect(CompatibilityIdentity(rawValue: "xone-hid") == .xoneHID)
    #expect(CompatibilityIdentity(rawValue: "xbox360-hid") == .xbox360HID)
    #expect(!CompatibilityIdentity.allCases.contains(.xoneHID))
    #expect(CompatibilityIdentity.allCases.contains(.xbox360HID))

    #expect(CompatibilityIdentity(rawValue: "not-a-profile") == nil)
  }

  @Test func legacyPersistedIdentityStillSelectsLegacyBackend() throws {
    let decoded = try #require(CompatibilityIdentity(rawValue: "xone-hid"))
    let profile = CompatibilityOutputProfileCatalog.profile(for: decoded)
    let composition = try CompatibilityOutputCompositionFactory.make(identity: decoded)

    #expect(decoded == .xoneHID)
    #expect(profile.identity == .xoneHID)
    #expect(composition.profile.identity == .xoneHID)
  }

  @Test func legacyIdentityDecodesButIsRejectedForNewMutation() throws {
    let decoded = try #require(CompatibilityIdentity(rawValue: "xone-hid"))
    let decision = decoded.mutationDecision()

    #expect(decoded == .xoneHID)
    #expect(decision == .rejected(.legacyIdentityNotSelectable))
    #expect(
      CompatibilityIdentity.mutationDecision(for: "xone-hid")
        == .rejected(.legacyIdentityNotSelectable)
    )
  }

  @Test func selectableIdentitiesRemainAcceptedForMutation() {
    for identity in CompatibilityIdentity.allCases {
      #expect(identity.mutationDecision() == .accepted(identity))
    }
    #expect(
      CompatibilityIdentity.mutationDecision(for: "not-a-profile") == .rejected(.unknownIdentity)
    )
  }

  @Test func testUserSpaceSerialUsesStableHashedPhysicalIdentity() {
    let identifier = DeviceIdentifier(
      vendorID: 13623,
      productID: 4112,
      serialNumber: "physical-serial"
    )
    let serial = UserSpaceVirtualDeviceConstants.serialNumber(for: identifier)

    #expect(serial.hasPrefix(UserSpaceVirtualDeviceConstants.serialPrefix))
    #expect(serial.count == UserSpaceVirtualDeviceConstants.serialPrefix.count + 16)
    #expect(serial.suffix(16).allSatisfy { $0.isHexDigit })
    #expect(serial == UserSpaceVirtualDeviceConstants.serialNumber(for: identifier))
  }

  @Test func testCompatibilityProfileCatalog() {
    let generic = CompatibilityOutputProfileCatalog.profile(for: .genericHID)
    let sdl = CompatibilityOutputProfileCatalog.profile(for: .sdl2_3)
    let apple = CompatibilityOutputProfileCatalog.profile(for: .appleGameController)
    let xone = CompatibilityOutputProfileCatalog.profile(for: .xoneHID)
    let xbox360 = CompatibilityOutputProfileCatalog.profile(for: .xbox360HID)

    #expect(generic.deviceProfile.productID == 0x4449)
    #expect(sdl.deviceProfile == .sdlHIDAPIXbox360)
    #expect(apple.deviceProfile == .xboxSeries)
    #expect(apple.deviceProfile.vendorID == 0x045E)
    #expect(apple.deviceProfile.productID == 0x0B13)
    #expect(apple.deviceProfile.transport == "Bluetooth")
    #expect(!generic.isHardwareSpoof)
    #expect(sdl.isHardwareSpoof)
    #expect(apple.isHardwareSpoof)
    #expect(sdl.deviceProfile.productName == "ASTRO C40 TR Controller")
    #expect(xone.isHardwareSpoof)
    #expect(xone.emitsXboxGuideReport)
    #expect(!apple.emitsXboxGuideReport)
    #expect(apple.evidence == .sourceBacked)
    #expect(xone.evidence == .sourceBacked)
    #expect(sdl.evidence == .hardwareVerified)
    #expect(generic.consumerFamily == .genericHID)
    #expect(sdl.consumerFamily == .sdlHIDAPI)
    #expect(!sdl.automaticallyRecommended)
    #expect(!apple.automaticallyRecommended)
    #expect(apple.consumerFamily == .appleGameController)
    #expect(apple.evidenceByConsumer[.chromiumGamepad] == .reportedFailure)
    #expect(xone.consumerFamily == .xboxOneHID)
    #expect(xone.evidenceByConsumer[.sdlHIDAPI] == .reportedFailure)
    #expect(xone.evidenceByConsumer[.appleGameController] == .sourceBacked)
    #expect(xbox360.deviceProfile == .xbox360Wired)
    #expect(xbox360.consumerFamily == .xbox360HID)
    #expect(xbox360.displayName == "Xbox 360 HID")
    #expect(xbox360.evidence == .researchOnly)
    #expect(CompatibilityEvidenceStatus.reportedFailure != .hardwareVerified)
    #expect(CompatibilityEvidenceStatus.researchOnly != .sourceBacked)
  }

  @Test func automaticResolverPreservesPhysicalFamilyBoundaries() {
    let xbox = ApplicationServiceDeviceDescription(
      name: "GameSir G7 SE",
      vendorID: 0x3537,
      productID: 0x1010,
      parser: "GIP",
      connection: "USB",
      serialNumber: nil,
      protocolVariant: .xboxOne
    )
    let otherXbox = ApplicationServiceDeviceDescription(
      name: "Xbox One",
      vendorID: 0x045E,
      productID: 0x02FD,
      parser: "GIP",
      connection: "Bluetooth",
      serialNumber: nil,
      protocolVariant: .xboxOne
    )
    let nintendo = ApplicationServiceDeviceDescription(
      name: "Switch",
      vendorID: 0x057E,
      productID: 0x2009,
      parser: "SwitchPro",
      connection: "USB",
      serialNumber: nil,
      protocolVariant: .switchPro
    )
    let ds4 = ApplicationServiceDeviceDescription(
      name: "DualShock 4",
      vendorID: 0x054C,
      productID: 0x05C4,
      parser: "DS4",
      connection: "USB",
      serialNumber: nil,
      protocolVariant: .dualShock4
    )
    let xinput = ApplicationServiceDeviceDescription(
      name: "XInput device",
      vendorID: 1,
      productID: 2,
      parser: "XInput",
      connection: "USB",
      serialNumber: nil,
      protocolVariant: .xboxOne
    )
    let xusb = ApplicationServiceDeviceDescription(
      name: "XUSB device",
      vendorID: 3,
      productID: 4,
      parser: "XUSB",
      connection: "USB",
      serialNumber: nil,
      protocolVariant: .xboxOne
    )
    #expect(AutomaticCompatibilityResolver.resolve(for: xbox).identity == .genericHID)
    #expect(AutomaticCompatibilityResolver.resolve(for: otherXbox).identity == .genericHID)
    #expect(AutomaticCompatibilityResolver.resolve(for: nintendo).identity == .genericHID)
    #expect(AutomaticCompatibilityResolver.resolve(for: ds4).identity == .genericHID)
    #expect(
      AutomaticCompatibilityResolver.resolve(for: xbox, consumer: .sdlHIDAPI).subfamily == .xboxGIP
    )
    #expect(
      AutomaticCompatibilityResolver.resolve(for: otherXbox, consumer: .appleGameController)
        .consumer == .appleGameController
    )
    #expect(AutomaticCompatibilityResolver.resolve(for: xinput).subfamily == .xboxGIP)
    #expect(AutomaticCompatibilityResolver.resolve(for: xusb).subfamily == .xboxGIP)
    #expect(
      AutomaticCompatibilityResolver.resolve(
        for: ApplicationServiceDeviceDescription(
          name: "Xbox 360",
          vendorID: 0x045E,
          productID: 0x028E,
          parser: "XUSB",
          connection: "USB",
          serialNumber: nil,
          protocolVariant: .xbox360
        )
      ).subfamily == .xbox360
    )
    #expect(AutomaticCompatibilityResolver.resolve(for: xbox).subfamily == .xboxGIP)
    #expect(AutomaticCompatibilityResolver.resolve(for: nintendo).subfamily != .xboxGIP)
    #expect(AutomaticCompatibilityResolver.resolve(for: ds4).subfamily != .xboxGIP)
    let failedBluetooth = AutomaticCompatibilityResolver.resolve(
      for: otherXbox,
      consumer: .sdlHIDAPI
    )
    #expect(failedBluetooth.identity == .genericHID)
    #expect(failedBluetooth.evidence == .reportedFailure)
    #expect(failedBluetooth.reason == .reportedConsumerFailure)

    let sameIdentityOverUSB = ApplicationServiceDeviceDescription(
      name: "Xbox One over USB",
      vendorID: 0x045E,
      productID: 0x02FD,
      parser: "GIP",
      connection: "USB",
      serialNumber: nil,
      protocolVariant: .xboxOne
    )
    let usbResolution = AutomaticCompatibilityResolver.resolve(
      for: sameIdentityOverUSB,
      consumer: .sdlHIDAPI
    )
    #expect(usbResolution.evidence == .unavailable)
    #expect(usbResolution.reason == .noAdjacentIdentity)
  }

  @Test func compatibilityFactoryKeepsProtocolTuplesAtomic() throws {
    let apple = try CompatibilityOutputCompositionFactory.make(identity: .appleGameController)
    let xone = try CompatibilityOutputCompositionFactory.make(identity: .xoneHID)
    let astro = try CompatibilityOutputCompositionFactory.make(identity: .sdl2_3)
    let xbox360 = try CompatibilityOutputCompositionFactory.make(identity: .xbox360HID)

    #expect(apple.profile.deviceProfile == .xboxSeries)
    #expect(xone.profile.deviceProfile == .xboxOneS)
    #expect(apple.format.descriptor == XboxOneBluetoothHIDDescriptor.seriesDescriptor)
    #expect(xone.format.descriptor == XboxOneBluetoothHIDDescriptor.descriptor)
    #expect(apple.format.inputReportID == 1)
    #expect(xone.format.inputReportID == 1)
    #expect(apple.format.outputReportID == VirtualRumbleOutputReportParser.xboxOneReportID)
    #expect(xone.format.outputReportID == VirtualRumbleOutputReportParser.xboxOneReportID)
    #expect(!apple.profile.emitsXboxGuideReport)
    #expect(xone.profile.emitsXboxGuideReport)
    #expect(astro.profile.deviceProfile == .sdlHIDAPIXbox360)
    #expect(astro.format.descriptor == Xbox360MacHIDReportFormat().descriptor)
    #expect(xbox360.profile.deviceProfile == .xbox360Wired)
    #expect(
      xbox360.format.descriptor
        == Xbox360MacHIDReportFormat(topLevelUsage: UInt8(kHIDUsage_GD_GamePad)).descriptor
    )
  }

  @Test func guideDispatchUsesXboxGuideReportContract() {
    #expect(UserSpaceOutputDispatcher.xboxGuideReport(for: .buttonPressed(.guide)) == [0x02, 0x01])
    #expect(UserSpaceOutputDispatcher.xboxGuideReport(for: .buttonReleased(.guide)) == [0x02, 0x00])
    #expect(UserSpaceOutputDispatcher.xboxGuideReport(for: .buttonPressed(.a)) == nil)
  }

  @Test func nonStandardButtonsKeepDistinctNormalizedBits() {
    let dispatcher = UserSpaceOutputDispatcher { _ in
      throw UserSpaceOutputDispatcher.CreationError.createFailed
    }

    #expect(dispatcher.buttonBit(for: .share) == 15)
    #expect(dispatcher.buttonBit(for: .genericButton1) == 16)
    #expect(dispatcher.buttonBit(for: .genericButton2) == 17)
    #expect(dispatcher.buttonBit(for: .genericButton3) == 18)
    #expect(dispatcher.buttonBit(for: .genericButton4) == 19)
    #expect(dispatcher.buttonBit(for: .genericButton5) == 20)
    #expect(dispatcher.buttonBit(for: .genericButton6) == 21)
    #expect(dispatcher.buttonBit(for: .genericButton7) == 22)
    #expect(dispatcher.buttonBit(for: .genericButton8) == 23)
  }

  @Test func testGenericReportDpadButtonPolicy() {
    let state = VirtualGamepadState(
      buttons: GamepadHIDDescriptor.dpadButtonBits(for: .north)
        | (1 << GamepadHIDDescriptor.ButtonBit.share.rawValue),
      hat: .north
    )

    let generic = OJDGenericGamepadFormat().buildInputReport(from: state)
    #expect((UInt16(generic[1]) & 0x88) == 0x88)
    #expect((generic[14] & 0x0F) == GamepadHIDDescriptor.Hat.north.rawValue)

    let sdl2_3 = OJDGenericGamepadFormat(includesDpadButtonBits: false).buildInputReport(
      from: state
    )
    #expect((UInt16(sdl2_3[1]) & 0x78) == 0)
    #expect((UInt16(sdl2_3[1]) & 0x80) == 0x80)
    #expect((sdl2_3[14] & 0x0F) == GamepadHIDDescriptor.Hat.north.rawValue)
  }

  @Test func testSdlReportUsesButtonDpadAndNeutralTriggers() throws {
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
    #expect(
      OJDSDLGamepadFormat().descriptor.containsSequence([
        0x09, 0x32,  // LT/Z
        0x15, 0x00,  // Logical Minimum: 0
        0x26, 0xFF, 0x7F
      ])
    )
    #expect(
      OJDSDLGamepadFormat().descriptor.containsSequence([
        0x09, 0x35,  // RT/Rz
        0x15, 0x00,  // Logical Minimum: 0
        0x26, 0xFF, 0x7F
      ])
    )
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

  @Test func testSdlRumbleOutputReportUsesVendorPayload() {
    #expect(SDLGamepadHIDDescriptor.maxOutputReportPayloadSize == 7)
    #expect(OJDSDLGamepadFormat().outputReportPayloadSize == 7)
    #expect(
      OJDSDLGamepadFormat().descriptor.containsSequence([
        0x06, 0x00, 0xFF,  // vendor-defined output page
        0x09, 0x01, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x07, 0x91, 0x02
      ])
    )
  }

  @Test func testUserSpaceSDLIdentityAdvertisesXbox360HIDAPIReportSizes() {
    let format = Xbox360MacHIDReportFormat()
    let properties = UserSpaceOutputDispatcher.deviceProperties(
      profile: .sdlHIDAPIXbox360,
      format: format,
      identifier: DeviceIdentifier(vendorID: 13623, productID: 4112)
    )

    let inputSize = properties[kIOHIDMaxInputReportSizeKey as String] as? Int
    let outputSize = properties[kIOHIDMaxOutputReportSizeKey as String] as? Int
    #expect(inputSize == format.inputReportPayloadSize)
    #expect(outputSize == format.outputReportPayloadSize)
  }

  @available(macOS 15, *) @Test func testCoreHIDPropertiesPreserveDescriptorAndIdentity() {
    let format = Xbox360MacHIDReportFormat()
    let properties = UserSpaceOutputDispatcher.virtualDeviceProperties(
      profile: .sdlHIDAPIXbox360,
      format: format,
      identifier: DeviceIdentifier(vendorID: 13623, productID: 4112)
    )

    #expect(properties.descriptor == Data(format.descriptor))
    #expect(properties.vendorID == UInt32(VirtualDeviceProfile.sdlHIDAPIXbox360.vendorID))
    #expect(properties.productID == UInt32(VirtualDeviceProfile.sdlHIDAPIXbox360.productID))
  }

  @Test func testUserSpaceDispatcherFailsFastWithoutVirtualDeviceEntitlement() throws {
    guard !UserSpaceOutputDispatcher.hasRequiredVirtualDeviceEntitlement else { return }

    do {
      _ = try UserSpaceOutputDispatcher()
      Issue.record("UserSpaceOutputDispatcher should require the virtual HID entitlement")
    } catch UserSpaceOutputDispatcher.CreationError.missingEntitlement(let entitlement) {
      #expect(entitlement == UserSpaceOutputDispatcher.requiredVirtualDeviceEntitlement)
    } catch { Issue.record("Unexpected error: \(error)") }
  }

  @Test func testXbox360FormatDefaultsToJoystickPrimaryUsage() {
    #expect(
      UserSpaceOutputDispatcher.defaultPrimaryUsage(for: Xbox360MacHIDReportFormat())
        == kHIDUsage_GD_Joystick
    )
  }

  @Test func testXbox360GamePadFormatDefaultsToGamePadPrimaryUsage() {
    #expect(
      UserSpaceOutputDispatcher.defaultPrimaryUsage(
        for: Xbox360MacHIDReportFormat(topLevelUsage: UInt8(kHIDUsage_GD_GamePad))
      ) == kHIDUsage_GD_GamePad
    )
  }

  @Test func testXboxOneCompatibilityFormatDeclaresRumbleOutputSize() throws {
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

  @Test func testSyntheticAppleGameControllerDevicesAreExcluded() {
    #expect(UserSpaceVirtualDeviceConstants.isAppleGameControllerSyntheticDevice(true))
    #expect(!UserSpaceVirtualDeviceConstants.isAppleGameControllerSyntheticDevice(false))
    var numericValue: Int32 = 1
    let numeric = withUnsafePointer(to: &numericValue) { CFNumberCreate(nil, .sInt32Type, $0) }
    #expect(!UserSpaceVirtualDeviceConstants.isAppleGameControllerSyntheticDevice(numeric))
    #expect(!UserSpaceVirtualDeviceConstants.isAppleGameControllerSyntheticDevice(nil))
  }

  @Test func physicalHIDAdmissionRejectsEveryIndependentVirtualDeviceMarker() {
    let physicalLocation: UInt32 = 1_114_112
    let virtualLocation = UserSpaceVirtualDeviceConstants.locationID(
      for: DeviceIdentifier(vendorID: 0x3537, productID: 0x1010, locationID: physicalLocation)
    )

    func accepts(
      serialNumber: String? = "physical-serial",
      productName: String? = "GameSir-G7 SE Controller for Xbox",
      transport: String? = "USB",
      locationID: UInt32 = physicalLocation,
      syntheticProperty: Any? = kCFBooleanFalse
    ) -> Bool {
      PhysicalHIDBackendEventPolicy.acceptsDevice(
        serialNumber: serialNumber,
        productName: productName,
        transport: transport,
        locationID: locationID,
        syntheticProperty: syntheticProperty
      )
    }

    #expect(accepts())
    #expect(!accepts(serialNumber: UserSpaceVirtualDeviceConstants.serialPrefix + "opaque"))
    #expect(!accepts(productName: UserSpaceVirtualDeviceConstants.product))
    #expect(!accepts(transport: "Virtual"))
    #expect(!accepts(transport: "virtual"))
    #expect(!accepts(locationID: virtualLocation))
    #expect(!accepts(syntheticProperty: kCFBooleanTrue))
  }

  @Test func compatibilitySpoofRemainsExcludedWhenAppleOmitsSerialAndSyntheticProperties() {
    let physical = DeviceIdentifier(
      vendorID: 0x3537,
      productID: 0x1010,
      serialNumber: "physical-serial",
      locationID: 1_114_112
    )
    let virtualLocation = UserSpaceVirtualDeviceConstants.locationID(for: physical)

    #expect(
      !PhysicalHIDBackendEventPolicy.acceptsDevice(
        serialNumber: nil,
        productName: "Xbox One S Controller",
        transport: "Bluetooth",
        locationID: virtualLocation,
        syntheticProperty: nil
      )
    )
  }

  @Test func syntheticFilteringPolicyCoversEveryPhysicalHIDBoundary() {
    let events: [UserSpaceVirtualDeviceConstants.PhysicalHIDEvent] = [
      .deviceAdded, .inputReport, .inputValue, .deviceRemoved, .descriptorDiscovery, .feedback
    ]
    for event in events {
      #expect(
        !UserSpaceVirtualDeviceConstants.acceptsPhysicalHIDEvent(
          event,
          syntheticProperty: kCFBooleanTrue
        )
      )
      #expect(
        UserSpaceVirtualDeviceConstants.acceptsPhysicalHIDEvent(
          event,
          syntheticProperty: kCFBooleanFalse
        )
      )
    }
  }

  @Test func physicalHIDTrackingEngineModelsSyntheticAndPhysicalEventSequences() {
    var engine = PhysicalHIDTrackingStateMachine()
    var disconnectCount = 0
    let synthetic = engine.register(deviceID: 1, locationID: 101, syntheticProperty: kCFBooleanTrue)
    #expect(!synthetic)
    #expect(!engine.acceptsInput(deviceID: 1))
    #expect(!engine.acceptsFeedback(locationID: 101))
    let syntheticRemoval = engine.remove(deviceID: 1)
    #expect(!syntheticRemoval)

    let physicalRegistration = engine.register(
      deviceID: 2,
      locationID: 202,
      syntheticProperty: kCFBooleanFalse
    )
    #expect(physicalRegistration)
    #expect(engine.acceptsInput(deviceID: 2))
    #expect(engine.acceptsInput(locationID: 202))
    #expect(engine.acceptsFeedback(locationID: 202))
    let physicalRemoval = engine.remove(deviceID: 2)
    if physicalRemoval { disconnectCount += 1 }
    #expect(!engine.acceptsInput(locationID: 202))
    #expect(!engine.acceptsFeedback(locationID: 202))
    let staleRemoval = engine.remove(deviceID: 2)
    #expect(!staleRemoval)
    if staleRemoval { disconnectCount += 1 }
    #expect(disconnectCount == 1)
  }

  @Test func bothProductionBackendsUseTheCentralSyntheticPolicy() {
    let events: [UserSpaceVirtualDeviceConstants.PhysicalHIDEvent] = [
      .deviceAdded, .inputReport, .inputValue, .deviceRemoved, .descriptorDiscovery, .feedback
    ]
    for event in events {
      #expect(
        PhysicalHIDBackendEventPolicy.accepts(event, syntheticProperty: kCFBooleanTrue) == false
      )
      #expect(PhysicalHIDBackendEventPolicy.accepts(event, syntheticProperty: kCFBooleanFalse))
    }
  }

  @Test func productionBackendAdaptersRejectSyntheticSharedLocationAndCleanPhysicalState() {
    var ioHID = PhysicalHIDBackendEventAdapter()
    var coreHID = PhysicalHIDBackendEventAdapter()

    for adapter in [ioHID, coreHID] {
      var adapter = adapter
      let syntheticAdded = adapter.add(
        deviceID: 2,
        locationID: 77,
        syntheticProperty: kCFBooleanTrue
      )
      #expect(!syntheticAdded)
      #expect(!adapter.acceptsInput(deviceID: 2))
      #expect(!adapter.acceptsFeedback(locationID: 77))
      #expect(!adapter.remove(deviceID: 2).wasTracked)
    }

    let physicalAdded = ioHID.add(deviceID: 1, locationID: 77, syntheticProperty: kCFBooleanFalse)
    let syntheticAdded = ioHID.add(deviceID: 2, locationID: 77, syntheticProperty: kCFBooleanTrue)
    #expect(physicalAdded)
    #expect(!syntheticAdded)
    #expect(ioHID.acceptsInput(deviceID: 1))
    #expect(!ioHID.acceptsInput(deviceID: 2))
    #expect(ioHID.acceptsFeedback(locationID: 77))
    let rejectedRemoval = ioHID.remove(deviceID: 2)
    #expect(!rejectedRemoval.wasTracked)
    let physicalRemoval = ioHID.remove(deviceID: 1)
    #expect(physicalRemoval.wasTracked)
    #expect(physicalRemoval.shouldCancelNotification)
    #expect(physicalRemoval.shouldEmitDisconnect)
    #expect(!ioHID.acceptsFeedback(locationID: 77))
    #expect(!ioHID.remove(deviceID: 1).shouldEmitDisconnect)

    let coreAdded = coreHID.add(deviceID: 1, locationID: 77, syntheticProperty: kCFBooleanFalse)
    #expect(coreAdded)
    let coreRemoval = coreHID.remove(deviceID: 1)
    #expect(coreRemoval.wasTracked)
    #expect(coreRemoval.shouldCancelNotification)
    #expect(coreRemoval.shouldEmitDisconnect)
  }

  @Test func synchronizedProductionAdapterSerializesConcurrentLifecycleAndFeedback() {
    let holder = SynchronizedPhysicalHIDBackendEventAdapter()
    let recorder = RemovalDecisionRecorder()

    for iteration in 0..<100 {
      holder.reset()
      let added = holder.add(
        deviceID: 1,
        locationID: UInt32(iteration),
        syntheticProperty: kCFBooleanFalse
      )
      #expect(added)
      recorder.reset()
      DispatchQueue.concurrentPerform(iterations: 64) { index in
        switch index % 4 {
        case 0: _ = holder.acceptsInput(deviceID: 1)
        case 1: _ = holder.acceptsFeedback(locationID: UInt32(iteration))
        case 2:
          let decision = holder.remove(deviceID: 1)
          recorder.append(decision)
        default: _ = holder.acceptsDescriptor(syntheticProperty: kCFBooleanFalse)
        }
      }

      #expect(recorder.disconnectCount() == 1)
      #expect(!holder.acceptsInput(deviceID: 1))
      #expect(!holder.acceptsFeedback(locationID: UInt32(iteration)))
    }

    DispatchQueue.concurrentPerform(iterations: 128) { index in
      if index.isMultiple(of: 5) {
        holder.reset()
      } else if index % 5 == 1 {
        _ = holder.add(
          deviceID: UInt64(index + 10),
          locationID: 999,
          syntheticProperty: kCFBooleanFalse
        )
      } else if index % 5 == 2 {
        _ = holder.acceptsInput(deviceID: UInt64(index + 10))
      } else if index % 5 == 3 {
        _ = holder.acceptsFeedback(locationID: 999)
      } else {
        _ = holder.remove(deviceID: UInt64(index + 10))
      }
    }
    holder.reset()
    #expect(!holder.acceptsInput(deviceID: 10))
    #expect(!holder.acceptsFeedback(locationID: 999))
  }

  @Test func testXboxGIPCompatibilityFormatAdvertisesFullOutputSize() throws {
    let format = try HIDDescriptorReportFormat(
      descriptor: XboxOneBluetoothHIDDescriptor.descriptor,
      outputReportID: VirtualRumbleOutputReportParser.xboxGIPReportID,
      outputReportPayloadSize: VirtualRumbleOutputReportParser
        .xboxGIPReportPayloadSizeWithoutReportID
    )
    let properties = UserSpaceOutputDispatcher.deviceProperties(
      profile: .xboxOneS,
      format: format,
      identifier: DeviceIdentifier(vendorID: 13623, productID: 4112)
    )

    let outputSize = properties[kIOHIDMaxOutputReportSizeKey as String] as? Int
    #expect(outputSize == 13)
  }

  @Test func testFixedCompatibilityReportHasNoHatAxis() throws {
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

  @Test func testCompatibilityFormatsReturnFullyNeutralReportsAfterRelease() throws {
    let generic = OJDGenericGamepadFormat().buildInputReport(from: VirtualGamepadState())
    let sdl = OJDSDLGamepadFormat().buildInputReport(from: VirtualGamepadState())
    let apple = Xbox360MacHIDReportFormat(topLevelUsage: UInt8(kHIDUsage_GD_GamePad))
      .buildInputReport(from: VirtualGamepadState())
    let x360 = Xbox360MacHIDReportFormat().buildInputReport(from: VirtualGamepadState())
    let xone = try HIDDescriptorReportFormat(descriptor: XboxOneBluetoothHIDDescriptor.descriptor)
      .buildInputReport(from: VirtualGamepadState())

    #expect(generic == [UInt8](repeating: 0, count: generic.count))
    #expect(sdl == [UInt8](repeating: 0, count: sdl.count))
    #expect(Array(apple.dropFirst(2)) == [UInt8](repeating: 0, count: apple.count - 2))
    #expect(Array(x360.dropFirst(2)) == [UInt8](repeating: 0, count: x360.count - 2))
    #expect(xone[0] == 1)
    #expect(xone[13] == 0x00)
    #expect(xone[14] == 0x00)
    #expect(xone[15] == 0x00)
    #expect(xone.count == 16)
  }

  @Test func userSpaceCreationErrorsDistinguishPermissionFromEntitlementAndCreation() {
    let errors: [UserSpaceOutputDispatcher.CreationError] = [
      .inputMonitoringDenied, .accessibilityDenied, .createFailed, .missingEntitlement("test")
    ]
    for error in errors {
      switch error {
      case .inputMonitoringDenied, .accessibilityDenied, .createFailed, .missingEntitlement: break
      }
    }
  }

}

extension Array where Element: Equatable {
  func containsSequence(_ sequence: [Element]) -> Bool {
    guard !sequence.isEmpty, sequence.count <= count else { return false }
    return indices.dropLast(sequence.count - 1).contains { index in
      self[index..<(index + sequence.count)].elementsEqual(sequence)
    }
  }

}
