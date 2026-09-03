import Testing

@testable import OpenJoystickDriverKit

struct USBDetectionAdmissionTests {
  @Test func unsupportedDeviceNeverInvokesProfileResolution() async {
    let provider = USBDiscoveryRecordingProvider(devices: [])
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      usbTransportProvider: provider
    )
    let unknown = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 1,
      vendorID: 65_535,
      productID: 65_535,
      locationID: 1
    )

    #expect(await manager.handleUSBDeviceAdded(unknown, provider: provider) == .ignored)
    #expect(await provider.resolutionCount == 0)
  }

  @Test func rejectedDeviceDoesNotReadOptionalDescriptorStrings() {
    var didReadDescriptorStrings = false

    let admission = resolveRawUSBAdmission(
      parserRegistry: ParserRegistry(),
      vendorID: 65_535,
      productID: 65_535,
      locationID: 1
    ) {
      didReadDescriptorStrings = true
      return (serialNumber: "unexpected", productName: "unexpected")
    }

    #expect(admission == nil)
    #expect(!didReadDescriptorStrings)
  }

  @Test func admittedDeviceReadsDescriptorStringsAndBuildsItsRuntimeIdentity() throws {
    var descriptorReadCount = 0

    let admission = try #require(
      resolveRawUSBAdmission(
        parserRegistry: ParserRegistry(),
        vendorID: 1_118,
        productID: 721,
        locationID: 513
      ) {
        descriptorReadCount += 1
        return (serialNumber: "serial", productName: "Xbox Controller")
      }
    )

    #expect(descriptorReadCount == 1)
    #expect(admission.identifier.vendorID == 1_118)
    #expect(admission.identifier.productID == 721)
    #expect(admission.identifier.serialNumber == "serial")
    #expect(admission.identifier.locationID == 513)
    #expect(admission.productName == "Xbox Controller")
  }

  @Test func duplicateTransportIdentityMatchesByModelAndSerialAcrossLocations() throws {
    let hidIdentifier = DeviceIdentifier(
      vendorID: 0x045E,
      productID: 0x0B12,
      serialNumber: "3039373130313939353733343337",
      locationID: 17_825_792
    )
    let rawUSBIdentifier = DeviceIdentifier(
      vendorID: 0x045E,
      productID: 0x0B12,
      serialNumber: "3039373130313939353733343337",
      locationID: 257
    )

    let match = try #require(
      DeviceManager.matchingPhysicalIdentifier(for: rawUSBIdentifier, among: [hidIdentifier])
    )

    #expect(match == hidIdentifier)
  }

  @Test func distinctControllerSerialsRemainSeparate() {
    let first = DeviceIdentifier(
      vendorID: 0x045E,
      productID: 0x0B12,
      serialNumber: "first",
      locationID: 1
    )
    let second = DeviceIdentifier(
      vendorID: 0x045E,
      productID: 0x0B12,
      serialNumber: "second",
      locationID: 2
    )

    #expect(DeviceManager.matchingPhysicalIdentifier(for: second, among: [first]) == nil)
  }

  @Test func competingPhysicalUSBRouteSkipsDescriptorResolution() async {
    let direct = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 1,
      vendorID: 1_118,
      productID: 721,
      locationID: 9,
      serialNumber: "serial"
    )
    let driverKit = USBTransportDevice(
      route: .usbDriverKit,
      serviceID: 2,
      vendorID: 1_118,
      productID: 721,
      locationID: 10,
      serialNumber: "serial"
    )
    let provider = USBDiscoveryRecordingProvider(devices: [direct, driverKit])
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      usbTransportProvider: provider
    )

    #expect(
      await manager.handleUSBDeviceAdded(direct, provider: provider)
        == .claimed(
          DeviceIdentifier(vendorID: 1_118, productID: 721, serialNumber: "serial", locationID: 9)
        )
    )
    #expect(await provider.resolutionCount == 1)

    #expect(await manager.handleUSBDeviceAdded(driverKit, provider: provider) == .retry)
    #expect(await provider.resolutionCount == 1)
    await manager.stop()
  }

  @Test func unresolvedServiceIsRetriedAfterItDisappears() async {
    let device = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 11,
      vendorID: 1_118,
      productID: 721,
      locationID: 9
    )
    let provider = USBDiscoveryRecordingProvider(devices: [])
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      usbTransportProvider: provider
    )

    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .retry)
    await provider.setDevices([device])
    #expect(
      await manager.handleUSBDeviceAdded(device, provider: provider)
        == .claimed(DeviceIdentifier(vendorID: 1_118, productID: 721, locationID: 9))
    )
  }

  @Test func serviceReuseWithChangedDeviceFactsRemainsUnacknowledged() async {
    let original = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 11,
      vendorID: 0x045E,
      productID: 0x02D1,
      locationID: 9
    )
    let replacement = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 11,
      vendorID: 0x3537,
      productID: 0x1010,
      locationID: 10
    )
    let provider = USBDiscoveryRecordingProvider(devices: [replacement])
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      usbTransportProvider: provider
    )

    #expect(await manager.handleUSBDeviceAdded(original, provider: provider) == .retry)
  }

  @Test func competingClaimsRetryAfterPostAwaitRecheckAndLaterClaimWithoutReplug() async {
    let device = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 11,
      vendorID: 1_118,
      productID: 721,
      locationID: 9
    )
    let provider = USBResolutionRaceProvider(device: device)
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      usbTransportProvider: provider
    )

    let firstClaim = Task { await manager.handleUSBDeviceAdded(device, provider: provider) }
    let secondClaim = Task { await manager.handleUSBDeviceAdded(device, provider: provider) }
    await provider.waitForResolutionCount(2)

    await provider.resumeNextResolution()
    await provider.waitForOpenCount(1)
    await provider.resumeNextResolution()

    let outcomes = [await firstClaim.value, await secondClaim.value]
    #expect(
      outcomes.contains(.claimed(DeviceIdentifier(vendorID: 1_118, productID: 721, locationID: 9)))
    )
    #expect(outcomes.contains(.retry))
    #expect(await provider.openCount == 1)

    await manager.stop()
    await provider.setResolutionSuspended(false)

    #expect(
      await manager.handleUSBDeviceAdded(device, provider: provider)
        == .claimed(DeviceIdentifier(vendorID: 1_118, productID: 721, locationID: 9))
    )
    await provider.waitForOpenCount(2)
    #expect(await provider.openCount == 2)
    await manager.stop()
  }
}

private actor USBDiscoveryRecordingProvider: USBTransportProvider {
  private var currentDevices: [USBTransportDevice]
  private(set) var resolutionCount = 0

  init(devices: [USBTransportDevice]) { currentDevices = devices }

  func devices() -> [USBTransportDevice] { currentDevices }

  func setDevices(_ devices: [USBTransportDevice]) { currentDevices = devices }

  func resolveTransportProfile(for device: USBTransportDevice, configured: DeviceTransportProfile)
    -> DeviceTransportProfile
  {
    resolutionCount += 1
    return configured
  }

  func open(_ device: USBTransportDevice, options: USBTransportOpenOptions)
    -> any USBTransportSession
  { USBDiscoveryRecordingSession() }
}

private final class USBDiscoveryRecordingSession: USBTransportSession, @unchecked Sendable {
  func writeInterruptPacket(endpoint: UInt8, data: [UInt8], timeout: UInt32) -> Int { data.count }

  func readInterruptPacket(endpoint: UInt8, length: Int, timeout: UInt32) throws -> [UInt8] {
    throw USBTransportError.disconnected
  }
}

private actor USBResolutionRaceProvider: USBTransportProvider {
  private let device: USBTransportDevice
  private let session = USBDiscoveryRecordingSession()
  private var resolutionSuspended = true
  private var resolutionContinuations: [CheckedContinuation<Void, Never>] = []
  private var resolutionWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private var openWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private(set) var resolutionCount = 0
  private(set) var openCount = 0

  init(device: USBTransportDevice) { self.device = device }

  func devices() -> [USBTransportDevice] { [device] }

  func resolveTransportProfile(for device: USBTransportDevice, configured: DeviceTransportProfile)
    async -> DeviceTransportProfile
  {
    resolutionCount += 1
    signalWaiters(&resolutionWaiters, count: resolutionCount)
    if resolutionSuspended { await withCheckedContinuation { resolutionContinuations.append($0) } }
    return configured
  }

  func open(_ device: USBTransportDevice, options: USBTransportOpenOptions)
    -> any USBTransportSession
  {
    openCount += 1
    signalWaiters(&openWaiters, count: openCount)
    return session
  }

  func waitForResolutionCount(_ count: Int) async {
    guard resolutionCount < count else { return }
    await withCheckedContinuation { resolutionWaiters.append((count, $0)) }
  }

  func resumeNextResolution() { resolutionContinuations.removeFirst().resume() }

  func waitForOpenCount(_ count: Int) async {
    guard openCount < count else { return }
    await withCheckedContinuation { openWaiters.append((count, $0)) }
  }

  func setResolutionSuspended(_ suspended: Bool) { resolutionSuspended = suspended }

  private func signalWaiters(_ waiters: inout [(Int, CheckedContinuation<Void, Never>)], count: Int)
  {
    var remaining: [(Int, CheckedContinuation<Void, Never>)] = []
    for (target, continuation) in waiters {
      if count >= target { continuation.resume() } else { remaining.append((target, continuation)) }
    }
    waiters = remaining
  }
}
