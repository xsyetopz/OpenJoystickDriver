import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// A raw-USB device whose configuration descriptor cannot be read gets one named outcome: held
/// with `DeviceInUse` while the host reports an exclusive owner, or `ConfigurationUnreadable`
/// when nothing OJD observes clears the failure.
struct USBHeldDeviceTests {
  private let device = USBTransportDevice(
    route: .rawUSB,
    serviceID: 0x3a32,
    vendorID: 0x3537,
    productID: 0x1010,
    locationID: 0x0113_0000
  )

  private func makeProvider(
    owner: String?,
    interfaceOwner: String? = nil,
    readError: USBTransportError? = .accessDenied,
    device: USBTransportDevice? = nil
  ) -> HeldDeviceProvider {
    let device = device ?? self.device
    return HeldDeviceProvider(
      device: device,
      passive: PhysicalDevice(
        serviceAddress: device.serviceAddress,
        vendorID: device.vendorID,
        productID: device.productID,
        configurationValue: 1,
        interfaces: [
          PhysicalInterfaceSignature(
            interfaceNumber: 0,
            alternateSetting: 0,
            interfaceClass: 0xFF,
            interfaceSubclass: 0x47,
            interfaceProtocol: 0xD0,
            endpoints: nil
          )
        ]
      ),
      owner: owner,
      readError: readError,
      interfaceOwner: interfaceOwner
    )
  }

  private func makeManager(_ provider: HeldDeviceProvider) -> DeviceManager {
    DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )
  }

  /// Runs `polls` enumeration polls of the device through the tracker, as the detection loop does.
  private func poll(
    _ polls: Int,
    _ manager: DeviceManager,
    _ provider: HeldDeviceProvider,
    _ enumeration: inout USBEnumerationTracker,
    device: USBTransportDevice? = nil
  ) async -> [USBDeviceHandlingOutcome] {
    let device = device ?? self.device
    var outcomes: [USBDeviceHandlingOutcome] = []
    for _ in 0..<polls {
      for event in enumeration.events(for: .available([device])) {
        guard case .attached(let attached) = event else { continue }
        let outcome = await manager.handleUSBDeviceAdded(attached, provider: provider)
        outcomes.append(outcome)
        if outcome == .ignored { enumeration.acknowledge(attached) }
      }
    }
    return outcomes
  }

  @Test
  func deniedDescriptorReadIsAcknowledgedAndReadOnce() async {
    let provider = makeProvider(owner: "pid 11070, steam_osx")
    let manager = makeManager(provider)
    var enumeration = USBEnumerationTracker()

    #expect(await poll(3, manager, provider, &enumeration) == [.ignored])
    #expect(await provider.descriptorReads == [1])
    #expect(await manager.unboundDeviceDescriptions().map(\.reason) == [.deviceInUse])
    #expect(await manager.heldUSBServices == [device.serviceAddress: "pid 11070, steam_osx"])
    await manager.stop()
  }

  /// The unbound device carries the product string the transport observed, and none when the
  /// string is missing or blank.
  @Test(
    arguments: [
      ("8BitDo Ultimate 2C Wireless Controller", "8BitDo Ultimate 2C Wireless Controller"),
      ("  IDLE \n", "IDLE"), ("   ", nil), ("", nil), (nil, nil),
    ] as [(String?, String?)]
  )
  func unboundDeviceCarriesObservedProductName(observed: String?, name: String?) async {
    let named = USBTransportDevice(
      route: .rawUSB,
      serviceID: device.serviceID,
      vendorID: device.vendorID,
      productID: device.productID,
      locationID: device.locationID,
      productName: observed
    )
    let provider = makeProvider(owner: "pid 11070, steam_osx", device: named)
    let manager = makeManager(provider)
    var enumeration = USBEnumerationTracker()

    _ = await poll(1, manager, provider, &enumeration, device: named)
    #expect(await manager.unboundDeviceDescriptions().map(\.name) == [name])
    await manager.stop()
  }

  /// The host answers a read of a device another client holds with `kIOReturnExclusiveAccess`.
  @Test(arguments: [nil, "pid 75592, steam_osx"])
  func exclusiveAccessRefusalIsHeldAndReadOnce(errorOwner: String?) async {
    let provider = makeProvider(
      owner: "pid 75592, steam_osx",
      readError: .ownedByAnotherClient(owner: errorOwner)
    )
    let manager = makeManager(provider)
    var enumeration = USBEnumerationTracker()

    #expect(await poll(3, manager, provider, &enumeration) == [.ignored])
    #expect(await provider.descriptorReads == [1])
    #expect(await manager.unboundDeviceDescriptions().map(\.reason) == [.deviceInUse])
    #expect(await manager.heldUSBServices == [device.serviceAddress: "pid 75592, steam_osx"])
    await manager.stop()
  }

  @Test
  func theDetectionLoopReadsAHeldDeviceOnceAcrossPolls() async {
    let provider = makeProvider(owner: "pid 11070, steam_osx")
    let manager = makeManager(provider)
    let detection = Task { await manager.runUSBDetection() }
    await waitUntil("the held device is recorded") {
      await manager.unboundDeviceDescriptions().count == 1
    }
    // Two more polls pass; the owner is read on each, the descriptor is not read again.
    let ownerReads = await provider.ownerReads
    await waitUntil("two more polls read the owner") { await provider.ownerReads >= ownerReads + 2 }
    #expect(await provider.descriptorReads == [1])
    #expect(await manager.unboundDeviceDescriptions().map(\.reason) == [.deviceInUse])
    detection.cancel()
    await detection.value
    await manager.stop()
  }

  @Test
  func heldServiceIsAdmittedAgainOnlyWhenItsHolderGoesAway() async {
    let provider = makeProvider(owner: "pid 11070, steam_osx")
    let manager = makeManager(provider)
    var enumeration = USBEnumerationTracker()
    let generation = await manager.lifecycleGeneration
    _ = await poll(1, manager, provider, &enumeration)

    await manager.releaseHeldUSBServices(
      in: &enumeration,
      provider: provider,
      generation: generation
    )
    #expect(enumeration.acknowledgedDevices[device.serviceAddress] != nil)

    // Another owner takes the device: it stays held.
    await provider.setOwner(.success("pid 22000, other_app"))
    await manager.releaseHeldUSBServices(
      in: &enumeration,
      provider: provider,
      generation: generation
    )
    #expect(enumeration.acknowledgedDevices[device.serviceAddress] != nil)
    #expect(await manager.heldUSBServices.count == 1)

    await provider.setOwner(.success(nil))
    await manager.releaseHeldUSBServices(
      in: &enumeration,
      provider: provider,
      generation: generation
    )
    #expect(enumeration.acknowledgedDevices.isEmpty)
    #expect(await manager.heldUSBServices.isEmpty)
    #expect(await manager.unboundDeviceDescriptions().isEmpty)
    await manager.stop()
  }

  /// The sequence seen with Steam: the read is refused while Steam holds the device, Steam quits,
  /// and the next poll admits the controller with no re-plug.
  @Test
  func theDetectionLoopAdmitsAHeldDeviceOnceItsOwnerQuits() async {
    let provider = makeProvider(owner: "pid 11070, steam_osx")
    let manager = makeManager(provider)
    let detection = Task { await manager.runUSBDetection() }
    await waitUntil("the held device is recorded") {
      await manager.unboundDeviceDescriptions().map(\.reason) == [.deviceInUse]
    }
    #expect(await provider.openCount == 0)

    await provider.release()
    await waitUntil("the released device is opened") { await provider.openCount == 1 }
    #expect(await provider.descriptorReads == [1, 1])
    #expect(await manager.heldUSBServices.isEmpty)
    #expect(await manager.unboundDeviceDescriptions().isEmpty)
    #expect(await manager.connectedDeviceDescriptions().count == 1)
    detection.cancel()
    await detection.value
    await manager.stop()
  }

  /// Steam holds only interface 0: the device names no owner, so the interface owner decides.
  @Test
  func anInterfaceOwnerHoldsTheServiceUntilItReleasesWithoutReenumeration() async {
    let provider = makeProvider(owner: nil, interfaceOwner: "pid 11070, steam_osx")
    let manager = makeManager(provider)
    var enumeration = USBEnumerationTracker()
    let generation = await manager.lifecycleGeneration

    #expect(await poll(1, manager, provider, &enumeration) == [.ignored])
    #expect(await manager.heldUSBServices == [device.serviceAddress: "pid 11070, steam_osx"])
    #expect(await manager.unboundDeviceDescriptions().map(\.reason) == [.deviceInUse])

    await manager.releaseHeldUSBServices(
      in: &enumeration,
      provider: provider,
      generation: generation
    )
    #expect(enumeration.acknowledgedDevices[device.serviceAddress] != nil)

    await provider.release()
    await manager.releaseHeldUSBServices(
      in: &enumeration,
      provider: provider,
      generation: generation
    )
    #expect(enumeration.acknowledgedDevices.isEmpty)
    #expect(await manager.heldUSBServices.isEmpty)
    #expect(await manager.unboundDeviceDescriptions().isEmpty)
    await manager.stop()
  }

  @Test
  func anUnreadableOwnerEndsTheWatchWithTheUnreadableReason() async {
    let provider = makeProvider(owner: "pid 11070, steam_osx")
    let manager = makeManager(provider)
    var enumeration = USBEnumerationTracker()
    let generation = await manager.lifecycleGeneration
    _ = await poll(1, manager, provider, &enumeration)

    await provider.setOwner(.failure(.notFound))
    await manager.releaseHeldUSBServices(
      in: &enumeration,
      provider: provider,
      generation: generation
    )
    #expect(await manager.heldUSBServices.isEmpty)
    #expect(await manager.unboundDeviceDescriptions().map(\.reason) == [.configurationUnreadable])
    #expect(enumeration.acknowledgedDevices[device.serviceAddress] != nil)

    let ownerReads = await provider.ownerReads
    await manager.releaseHeldUSBServices(
      in: &enumeration,
      provider: provider,
      generation: generation
    )
    #expect(await provider.ownerReads == ownerReads)
    await manager.stop()
  }

  @Test
  func deniedReadWithoutAnOwnerIsUnreadableUntilReenumeration() async {
    let provider = makeProvider(owner: nil)
    let manager = makeManager(provider)
    var enumeration = USBEnumerationTracker()
    let generation = await manager.lifecycleGeneration

    #expect(await poll(3, manager, provider, &enumeration) == [.ignored])
    await manager.releaseHeldUSBServices(
      in: &enumeration,
      provider: provider,
      generation: generation
    )
    #expect(enumeration.acknowledgedDevices[device.serviceAddress] != nil)
    #expect(await provider.descriptorReads == [1])
    #expect(await manager.heldUSBServices.isEmpty)
    #expect(await manager.unboundDeviceDescriptions().map(\.reason) == [.configurationUnreadable])
    await manager.stop()
  }

  @Test
  func otherReadFailuresAreBoundedThenNamed() async {
    let provider = makeProvider(owner: nil, readError: .inputOutput)
    let manager = makeManager(provider)
    var enumeration = USBEnumerationTracker()

    let outcomes = await poll(usbConfigurationReadAttempts + 3, manager, provider, &enumeration)
    #expect(
      outcomes == Array(repeating: .retry, count: usbConfigurationReadAttempts - 1) + [.ignored]
    )
    #expect(await provider.descriptorReads.count == usbConfigurationReadAttempts)
    #expect(await provider.ownerReads == 0)
    #expect(await manager.unboundDeviceDescriptions().map(\.reason) == [.configurationUnreadable])
    #expect(await manager.usbConfigurationReadFailures.isEmpty)
    await manager.stop()
  }

  @Test
  func aSuccessfulReadResetsTheFailedReadCount() async {
    let provider = makeProvider(owner: nil, readError: .inputOutput)
    let manager = makeManager(provider)
    var enumeration = USBEnumerationTracker()

    _ = await poll(usbConfigurationReadAttempts - 1, manager, provider, &enumeration)
    #expect(
      await manager.usbConfigurationReadFailures[device.serviceAddress]
        == usbConfigurationReadAttempts - 1
    )
    await provider.setReadError(nil)
    _ = await manager.handleUSBDeviceAdded(device, provider: provider)
    #expect(await manager.usbConfigurationReadFailures.isEmpty)
    await manager.stop()
  }

  @Test
  func aServiceThatLeavesBeforeAcknowledgementDropsItsFailedReadCount() async {
    let provider = makeProvider(owner: nil, readError: .inputOutput)
    let manager = makeManager(provider)
    var enumeration = USBEnumerationTracker()
    _ = await poll(1, manager, provider, &enumeration)
    #expect(await manager.usbConfigurationReadFailures.count == 1)

    await manager.pruneUSBConfigurationReadFailures(keeping: [])
    #expect(await manager.usbConfigurationReadFailures.isEmpty)
    await manager.stop()
  }

  @Test
  func stopDuringTheOwnerReadLeavesNoHold() async {
    let provider = makeProvider(owner: "pid 11070, steam_osx")
    await provider.blockOwnerRead()
    let manager = makeManager(provider)
    let admission = Task { await manager.handleUSBDeviceAdded(device, provider: provider) }
    await waitUntil("the owner read is in flight") { await provider.ownerReads == 1 }

    await manager.stop()
    await provider.releaseOwnerRead()
    #expect(await admission.value == .retry)
    #expect(await manager.heldUSBServices.isEmpty)
    #expect(await manager.unboundDeviceDescriptions().isEmpty)
  }
}

actor HeldDeviceProvider: USBTransportProvider {
  let device: USBTransportDevice
  let passive: PhysicalDevice
  private var owner: Result<String?, USBTransportError>
  private var readError: USBTransportError?
  private var interfaceOwner: String?
  private(set) var interfaceOwnerReads = 0
  private var ownerReadBlocked = false
  private var ownerReadWaiter: CheckedContinuation<Void, Never>?
  private(set) var descriptorReads: [UInt8] = []
  private(set) var ownerReads = 0
  private(set) var openCount = 0
  let session = USBManagerResolutionSession()

  /// The configuration read once the host allows it: the GIP interface with its interrupt pair.
  var configured: PhysicalDevice {
    PhysicalDevice(
      serviceAddress: passive.serviceAddress,
      vendorID: passive.vendorID,
      productID: passive.productID,
      configurationValue: 1,
      interfaces: (passive.interfaces ?? []).map {
        PhysicalInterfaceSignature(
          interfaceNumber: $0.interfaceNumber,
          alternateSetting: $0.alternateSetting,
          interfaceClass: $0.interfaceClass,
          interfaceSubclass: $0.interfaceSubclass,
          interfaceProtocol: $0.interfaceProtocol,
          endpoints: [
            PhysicalEndpointSignature(address: 0x82, direction: .in, transferType: .interrupt),
            PhysicalEndpointSignature(address: 0x02, direction: .out, transferType: .interrupt),
          ]
        )
      }
    )
  }

  init(
    device: USBTransportDevice,
    passive: PhysicalDevice,
    owner: String?,
    readError: USBTransportError?,
    interfaceOwner: String? = nil
  ) {
    self.device = device
    self.passive = passive
    self.owner = .success(owner)
    self.readError = readError
    self.interfaceOwner = interfaceOwner
  }

  func setOwner(_ owner: Result<String?, USBTransportError>) { self.owner = owner }

  func setReadError(_ error: USBTransportError?) { readError = error }

  /// The owner quits: the host reports no owner and allows the read.
  func release() {
    owner = .success(nil)
    interfaceOwner = nil
    readError = nil
  }

  func blockOwnerRead() { ownerReadBlocked = true }

  func releaseOwnerRead() {
    ownerReadBlocked = false
    ownerReadWaiter?.resume()
    ownerReadWaiter = nil
  }

  func devices() -> [USBTransportDevice] { [device] }

  func physicalDeviceObservation(for _: USBTransportDevice) -> PhysicalDevice? { passive }

  func resolveTransport(
    for _: USBTransportDevice,
    configured profile: DeviceTransportProfile
  ) -> USBTransportResolution { USBTransportResolution(profile: profile, physicalDevice: passive) }

  func configurationObservation(
    for _: USBTransportDevice,
    configurationValue: UInt8
  ) throws -> PhysicalDevice? {
    descriptorReads.append(configurationValue)
    if let readError { throw readError }
    return configured
  }

  func exclusiveOwner(of _: USBTransportDevice) async throws -> String? {
    ownerReads += 1
    if ownerReadBlocked { await withCheckedContinuation { ownerReadWaiter = $0 } }
    return try owner.get()
  }

  func interfaceExclusiveOwner(
    of _: USBTransportDevice,
    interfaceNumber _: UInt8
  ) -> String? {
    interfaceOwnerReads += 1
    return interfaceOwner
  }

  func open(
    _: USBTransportDevice,
    options _: USBTransportOpenOptions
  ) -> any USBTransportSession {
    openCount += 1
    return session
  }
}
