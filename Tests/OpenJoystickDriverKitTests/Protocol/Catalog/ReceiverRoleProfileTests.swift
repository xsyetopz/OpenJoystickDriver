import Testing

@testable import OpenJoystickDriverKit

/// `roleProfiles` per `xpad_probe` (xpad.c:2042–2137): one receiver role per FF/5D/81 interface
/// with exactly one interrupt IN and one interrupt OUT endpoint.
///
/// Every interface layout here is synthetic. Receiver slot interface numbers on macOS have not been
/// captured; 0/2/4/6 with a second triple on 1/3/5/7 only exercises the interface walk.
struct ReceiverRoleProfileTests {
  private let registry = ProtocolDriverRegistry()
  private let receiver = DeviceIdentifier(vendorID: 0x045E, productID: 0x0719, locationID: 7)

  @Test
  func eachReceiverInterfaceIsOneSlotInInterfaceOrder() throws {
    let binding = try bound(0x045E, 0x0719)
    // Synthetic: listed out of order, so the roles must sort by interface number.
    let roles = registry.roleProfiles(
      for: binding,
      resolution: claim(of: [6, 1, 0, 3, 4, 5, 2, 7].map(Self.syntheticInterface))
    )

    #expect(roles.map(\.profile.interfaceNumber) == [0, 2, 4, 6])
    #expect(roles.map(\.profile.inputEndpoint) == [0x81, 0x83, 0x85, 0x87])
    #expect(roles.map(\.profile.outputEndpoint) == [0x01, 0x03, 0x05, 0x07])
    for (ordinal, role) in roles.enumerated() {
      let driver = try registry.makeDriver(
        for: binding,
        identifier: receiver,
        claimed: role,
        slotOrdinal: ordinal
      ).get()
      // The manager's slot pool picks the player; each slot writes its LED on its own endpoint.
      let led = try #require(playerLED(driver))
      #expect(led.endpoint == role.profile.outputEndpoint)
    }
  }

  @Test
  func interfaceWithThreeEndpointsOrAnotherTripleIsNotARole() throws {
    let binding = try bound(0x045E, 0x0719)
    // Synthetic: interface 2 carries an extra endpoint and interface 1 the non-slot triple.
    let threeEndpoints = PhysicalInterfaceSignature(
      interfaceNumber: 2,
      alternateSetting: 0,
      interfaceClass: 0xFF,
      interfaceSubclass: 0x5D,
      interfaceProtocol: 0x81,
      endpoints: Self.interruptPair(input: 0x83, output: 0x03) + [
        PhysicalEndpointSignature(address: 0x84, direction: .in, transferType: .interrupt)
      ]
    )
    let roles = registry.roleProfiles(
      for: binding,
      resolution: claim(of: [
        Self.syntheticInterface(0), Self.syntheticInterface(1), threeEndpoints,
      ])
    )

    #expect(roles.map(\.profile.interfaceNumber) == [0])
  }

  @Test
  func matchingInterfaceBeyondTheFourthSlotIsDropped() throws {
    let binding = try bound(0x045E, 0x0719)
    // Synthetic: five slot interfaces.
    let roles = registry.roleProfiles(
      for: binding,
      resolution: claim(of: [0, 2, 4, 6, 8].map(Self.syntheticInterface))
    )

    #expect(roles.map(\.profile.interfaceNumber) == [0, 2, 4, 6])
  }

  @Test
  func onlyTheFirstSlotSetsTheConfiguration() throws {
    let binding = try bound(0x045E, 0x0719)
    // Synthetic: four slot interfaces on an unconfigured receiver.
    let resolution = claim(
      of: [0, 2, 4, 6].map(Self.syntheticInterface),
      needsSetConfiguration: true
    )

    let roles = registry.roleProfiles(for: binding, resolution: resolution)

    #expect(roles.map(\.profile.needsSetConfiguration) == [true, false, false, false])
  }

  @Test
  func pinnedReceiverClaimStaysItsOneRole() throws {
    let binding = try bound(0x045E, 0x0719)
    // Synthetic: four slot interfaces, but the claim carries catalog pins for interface 2.
    let pinned = USBTransportResolution(
      profile: DeviceTransportProfile(
        inputEndpoint: 0x83,
        outputEndpoint: 0x03,
        interfaceNumber: 2,
        hasInterfaceOverride: true,
        hasEndpointOverride: true,
        needsSetConfiguration: false
      ),
      physicalDevice: claim(of: [0, 2, 4, 6].map(Self.syntheticInterface)).physicalDevice
    )

    #expect(registry.roleProfiles(for: binding, resolution: pinned) == [pinned])
    #expect(
      registry.makeDriver(for: binding, identifier: receiver, claimed: pinned).failureReason == nil
    )
  }

  @Test
  func receiverWithoutAQualifyingInterfaceKeepsItsClaim() throws {
    let binding = try bound(0x045E, 0x0719)
    let unobserved = USBTransportResolution(profile: try profile(of: binding))

    #expect(registry.roleProfiles(for: binding, resolution: unobserved) == [unobserved])
  }

  @Test(arguments: [
    (UInt16(0x045E), UInt16(0x02D1)),  // xbox.gip:usb
    (UInt16(0x0079), UInt16(0x1832)),  // xbox.xusb:wired
    (UInt16(0x044F), UInt16(0x0F00)),  // xbox.xid:gamepad
    (UInt16(0x3537), UInt16(0x1003)),  // vendor.gamesir:usb
  ])
  func everyOtherFamilyRunsItsClaimAsItsOneRole(vendorID: UInt16, productID: UInt16) throws {
    let binding = try bound(vendorID, productID)
    // Synthetic: slot-shaped receiver interfaces must not split another family.
    let resolution = claim(of: [0, 2, 4, 6].map(Self.syntheticInterface))

    #expect(registry.roleProfiles(for: binding, resolution: resolution) == [resolution])
  }

  static func syntheticInterface(_ number: UInt8) -> PhysicalInterfaceSignature {
    PhysicalInterfaceSignature(
      interfaceNumber: number,
      alternateSetting: 0,
      interfaceClass: 0xFF,
      interfaceSubclass: 0x5D,
      // Even interfaces carry the receiver slot triple; odd ones another vendor triple.
      interfaceProtocol: number.isMultiple(of: 2) ? 0x81 : 0x82,
      endpoints: interruptPair(input: 0x81 + number, output: 0x01 + number)
    )
  }

  static func interruptPair(input: UInt8, output: UInt8) -> [PhysicalEndpointSignature] {
    [
      PhysicalEndpointSignature(address: input, direction: .in, transferType: .interrupt),
      PhysicalEndpointSignature(address: output, direction: .out, transferType: .interrupt),
    ]
  }

  private func claim(
    of interfaces: [PhysicalInterfaceSignature],
    needsSetConfiguration: Bool = false
  ) -> USBTransportResolution {
    USBTransportResolution(
      profile: DeviceTransportProfile(
        inputEndpoint: 0x81,
        outputEndpoint: 0x01,
        needsSetConfiguration: needsSetConfiguration
      ),
      physicalDevice: PhysicalDevice(
        vendorID: 0x045E,
        productID: 0x0719,
        configurationValue: 1,
        interfaces: interfaces
      )
    )
  }

  private func bound(_ vendorID: UInt16, _ productID: UInt16) throws -> ProtocolBinding {
    let classification = registry.classify(
      PhysicalDevice(vendorID: vendorID, productID: productID),
      backend: .ioUSBHost
    )
    guard case .bound(let binding) = classification else {
      Issue.record("did not bind: \(classification)")
      throw ReceiverRoleBindingFailure()
    }
    return binding
  }

  private func profile(of binding: ProtocolBinding) throws -> DeviceTransportProfile {
    try #require(registry.runtimeProfile(for: binding)).transportProfile
  }

  private func playerLED(_ driver: any PhysicalProtocolDriver) -> PhysicalUSBOutputPacket? {
    guard case .usb(let packet, _) = try? driver.encode(.setPlayerIndicator(.player1)).writes.first
    else { return nil }
    return packet
  }
}

private struct ReceiverRoleBindingFailure: Error {}
