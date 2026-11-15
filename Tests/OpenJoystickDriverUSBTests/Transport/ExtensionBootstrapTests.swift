import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverUSB

struct ExtensionBootstrapTests {
  static let descriptor: [UInt8] = [
    9, 2, 32, 0, 1, 1, 0, 128, 250,
    9, 4, 0, 0, 2, 255, 71, 208, 0,
    7, 5, 1, 3, 64, 0, 4,
    7, 5, 129, 3, 64, 0, 4,
  ]

  @Test(arguments: [nil, 0] as [UInt8?])
  func vacantDeviceUsesLiveConfigurationBeforePublishingInterfaces(registry: UInt8?) async throws {
    var writes = 0
    var reads = 0
    let configured = try await USBExtensionBootstrap.prepare(
      state: { state(configuration: registry) },
      descriptor: { Self.descriptor },
      currentConfiguration: {
        reads += 1
        return 0
      },
      configure: { writes += 1 }
    )
    #expect(configured)
    #expect(reads == 1)
    #expect(writes == 1)
  }

  @Test(arguments: [UInt8(1), 2])
  func configuredDevicesAreNeverOpenedOrReconfigured(configuration: UInt8) async throws {
    let result = try await USBExtensionBootstrap.prepare(
      state: { state(configuration: configuration) },
      descriptor: {
        Issue.record("Configured devices must not be inspected")
        return Self.descriptor
      },
      currentConfiguration: {
        Issue.record("No control read is needed")
        return 0
      },
      configure: { Issue.record("No configuration write is permitted") }
    )
    #expect(!result)
  }

  @Test(arguments: [true, false])
  func existingInterfaceOrOtherOwnerPreventsBootstrap(interface: Bool) async throws {
    let result = try await USBExtensionBootstrap.prepare(
      state: { state(hasInterfaces: interface, owned: !interface) },
      descriptor: {
        Issue.record("Owned devices must not be inspected")
        return Self.descriptor
      },
      currentConfiguration: {
        Issue.record("Owned devices must not be opened")
        return 0
      },
      configure: { Issue.record("Owned devices must not be reconfigured") }
    )
    #expect(!result)
  }

  @Test
  func liveConfigurationOneOverridesMissingRegistryProperty() async throws {
    let result = try await USBExtensionBootstrap.prepare(
      state: { state(configuration: nil) },
      descriptor: { Self.descriptor },
      currentConfiguration: { 1 },
      configure: { Issue.record("Live configuration 1 must not be repeated") }
    )
    #expect(!result)
  }

  @Test
  func ownerAppearingDuringControlReadPreventsConfigurationWrite() async throws {
    var controlRead = false
    let result = try await USBExtensionBootstrap.prepare(
      state: { state(owned: controlRead) },
      descriptor: { Self.descriptor },
      currentConfiguration: {
        controlRead = true
        return 0
      },
      configure: { Issue.record("Ownership changed before the configuration write") }
    )
    #expect(!result)
  }

  @Test
  func failedControlReadDoesNotGuessConfigurationZero() async {
    await #expect(throws: USBTransportError.timeout) {
      try await USBExtensionBootstrap.prepare(
        state: { state() },
        descriptor: { Self.descriptor },
        currentConfiguration: { throw USBTransportError.timeout },
        configure: { Issue.record("A failed read must not authorize a write") }
      )
    }
  }

  @Test
  func interfaceAppearingAfterDescriptorReadPreventsTheControlRequest() async throws {
    var descriptorRead = false
    let result = try await USBExtensionBootstrap.prepare(
      state: { state(hasInterfaces: descriptorRead) },
      descriptor: {
        descriptorRead = true
        return Self.descriptor
      },
      currentConfiguration: {
        Issue.record("An interface appeared before the control read")
        return 0
      },
      configure: { Issue.record("An existing interface must not be reconfigured") }
    )
    #expect(!result)
  }

  @Test
  func descriptorMustContainTheExtensionsGIPInterface() throws {
    #expect(try USBExtensionBootstrap.supportsGIPInterface(Self.descriptor))
    var hid = Self.descriptor
    hid[14] = 3
    #expect(try !USBExtensionBootstrap.supportsGIPInterface(hid))
    var wrongConfiguration = Self.descriptor
    wrongConfiguration[5] = 2
    #expect(try !USBExtensionBootstrap.supportsGIPInterface(wrongConfiguration))
    #expect(throws: PassiveUSBDescriptorBlobError.totalLengthMismatch) {
      try USBExtensionBootstrap.supportsGIPInterface(Array(Self.descriptor.dropLast()))
    }
  }

  private func state(
    configuration: UInt8? = 0,
    hasInterfaces: Bool = false,
    owned: Bool = false
  ) -> USBExtensionBootstrapState {
    USBExtensionBootstrapState(
      configuration: configuration,
      hasInterfaces: hasInterfaces,
      ownedByAnotherClient: owned
    )
  }
}
