import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct USBStartupOutputPolicyTests {
  /// The ring LED write a wired Xbox 360 pipeline sends after the manager assigns it a slot.
  private func xbox360RingLEDWrite() async throws -> PhysicalOutputWrite {
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 0x045E, productID: 0x028E),
      transport: .usb(device: Self.device),
      driver: XUSBDriver(),
      dispatcher: LoggingOutputDispatcher(),
      usbStartupPlayerIndicator: .player1
    )
    return try #require(await pipeline.usbStartupWrites().first)
  }

  @Test
  func defersVirtualOutputUntilThePhysicalUSBSessionOpens() async {
    let identifier = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let provider = ScriptedUSBTransportProvider(failuresBeforeSuccess: .max)
    let dispatcher = StartupRecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(device: Self.device),
      driver: StartupInputParser(),
      dispatcher: dispatcher,
      usbTransportProvider: provider,
      usbRecoveryPolicy: Self.fastRecoveryPolicy
    )

    let startTask = Task { await pipeline.start() }
    let retried = await waitUntil { await provider.openAttempts() >= 4 }

    #expect(retried)
    #expect(dispatcher.activations == 0)
    #expect(dispatcher.ownershipStates.contains(.accessDenied))
    #expect(!dispatcher.ownershipStates.contains(.exclusive))
    await pipeline.stop()
    await startTask.value
  }

  @Test
  func publishesVirtualOutputAfterARecoveredPhysicalUSBHandshake() async {
    let identifier = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let provider = ScriptedUSBTransportProvider(failuresBeforeSuccess: 3)
    let dispatcher = StartupRecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(device: Self.device),
      driver: StartupInputParser(),
      dispatcher: dispatcher,
      usbTransportProvider: provider,
      usbRecoveryPolicy: Self.fastRecoveryPolicy
    )

    let startTask = Task { await pipeline.start() }
    let published = await waitUntil { dispatcher.activations == 1 }

    #expect(published)
    #expect(await provider.openAttempts() == 4)
    #expect(dispatcher.activations == 1)
    #expect(dispatcher.ownershipAtDispatch == [.exclusive])
    await pipeline.stop()
    await startTask.value
    #expect(dispatcher.ownershipStates.last == .unknown)
  }

  @Test
  func recoveryBackoffIsBounded() {
    let policy = USBPipelineRecoveryPolicy(
      openRetryDelays: [1],
      reconnectBaseDelayNanoseconds: 10,
      reconnectMaximumDelayNanoseconds: 40,
      accessContentionDelayNanoseconds: 80
    )

    #expect(policy.reconnectDelayNanoseconds(after: 0) == 10)
    #expect(policy.reconnectDelayNanoseconds(after: 1) == 20)
    #expect(policy.reconnectDelayNanoseconds(after: 2) == 40)
    #expect(policy.reconnectDelayNanoseconds(after: 20) == 40)
    #expect(policy.accessContentionDelayNanoseconds == 80)
  }

  @Test
  func accessContentionSkipsWastefulImmediateOpenRetries() async {
    let provider = ScriptedUSBTransportProvider(failuresBeforeSuccess: .max)
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 0x3537, productID: 0x1010),
      transport: .usb(device: Self.device),
      driver: StartupInputParser(),
      dispatcher: StartupRecordingOutputDispatcher(),
      usbTransportProvider: provider,
      usbRecoveryPolicy: USBPipelineRecoveryPolicy(
        openRetryDelays: [1, 1, 1],
        reconnectBaseDelayNanoseconds: 1,
        reconnectMaximumDelayNanoseconds: 1,
        accessContentionDelayNanoseconds: 1
      )
    )

    let result = await pipeline.openDeviceWithRetry(provider: provider, device: Self.device)

    guard case .unavailable(.accessDenied) = result else {
      Issue.record("Expected exclusive ownership to be classified as access contention")
      return
    }
    #expect(await provider.openAttempts() == 1)
  }

  @Test
  func stopWhileOpenIsSuspendedCannotPublishOrOrphanVirtualOutput() async {
    let session = ClosingUSBTransportSession()
    let provider = SuspendedSuccessfulUSBTransportProvider(session: session)
    let dispatcher = StartupRecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 0x3537, productID: 0x1010),
      transport: .usb(device: Self.device),
      driver: StartupInputParser(),
      dispatcher: dispatcher,
      usbTransportProvider: provider,
      usbRecoveryPolicy: Self.fastRecoveryPolicy
    )

    let startTask = Task { await pipeline.start() }
    #expect(await waitUntil { await provider.hasStartedOpen() })

    await pipeline.stop()
    await provider.resumeOpen()
    await startTask.value

    #expect(dispatcher.activations == 0)
    #expect(await waitUntil { await session.closeCount() == 1 })
    #expect(!dispatcher.ownershipStates.contains(.exclusive))
  }

  @Test
  func ignoresIOErrorForXbox360RingLED() async throws {
    let write = try await xbox360RingLEDWrite()

    #expect(isIgnorableUSBStartupOutputError(write, error: .inputOutput))
  }

  @Test
  func ignoresUnsupportedErrorForXbox360RingLED() async throws {
    let write = try await xbox360RingLEDWrite()

    #expect(isIgnorableUSBStartupOutputError(write, error: .notSupported))
  }

  @Test
  func ignoresNotFoundErrorForXbox360RingLED() async throws {
    let write = try await xbox360RingLEDWrite()

    #expect(isIgnorableUSBStartupOutputError(write, error: .notFound))
  }

  @Test
  func ignoresTimeoutForXbox360RingLED() async throws {
    let write = try await xbox360RingLEDWrite()

    #expect(isIgnorableUSBStartupOutputError(write, error: .timeout))
  }

  @Test
  func preservesOtherXbox360StartupOutputFailures() async throws {
    let write = try await xbox360RingLEDWrite()
    let errors: [USBTransportError] = [
      .disconnected, .accessDenied, .platform(code: 1, message: "unexpected"),
    ]

    for error in errors { #expect(!isIgnorableUSBStartupOutputError(write, error: error)) }
  }

  @Test
  func preservesNotFoundForOtherStartupPacketsAndParsers() {
    let genericParser = HIDDescriptorDriver(identifier: DeviceIdentifier(vendorID: 1, productID: 2))

    #expect(!isIgnorableUSBStartupOutputError(Self.write([0x00, 0x01]), error: .notFound))
    #expect(!isIgnorableUSBStartupOutputError(Self.write([0x01, 0x03, 0x06]), error: .notFound))
    #expect(genericParser.startupWrites().isEmpty)
  }

  @Test
  func preservesIOErrorForOtherStartupPacketsAndParsers() {
    let genericParser = HIDDescriptorDriver(identifier: DeviceIdentifier(vendorID: 1, productID: 2))
    let error = USBTransportError.inputOutput

    #expect(!isIgnorableUSBStartupOutputError(Self.write([0x00, 0x01]), error: error))
    #expect(!isIgnorableUSBStartupOutputError(Self.write([0x01, 0x03, 0x06]), error: error))
    #expect(genericParser.startupWrites().isEmpty)
  }

  /// A startup write that does not tolerate rejection, whatever its bytes.
  private static func write(_ bytes: [UInt8]) -> PhysicalOutputWrite {
    .usb(PhysicalUSBOutputPacket(endpoint: 0x01, bytes: bytes, timeoutMilliseconds: 2_000))
  }

  private static let device = USBTransportDevice(
    route: .ioUSBHost,
    serviceID: 1,
    vendorID: 0x3537,
    productID: 0x1010,
    locationID: 1,
    productName: "GameSir G7 SE"
  )

  private static let fastRecoveryPolicy = USBPipelineRecoveryPolicy(
    openRetryDelays: [1_000_000],
    reconnectBaseDelayNanoseconds: 1_000_000,
    reconnectMaximumDelayNanoseconds: 4_000_000,
    accessContentionDelayNanoseconds: 1_000_000
  )

  private func waitUntil(
    timeoutNanoseconds: UInt64 = 10_000_000_000,
    condition: @escaping @Sendable () async -> Bool
  ) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds &+ timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
      if await condition() { return true }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return await condition()
  }
}

private final class StartupInputParser: PhysicalProtocolDriver {
  let capabilities = ControllerCapabilities(controls: ControlID.xboxLayout)
  let sessionPlan = DriverSessionPlan()
  let outputCapabilities = PhysicalControllerOutputCapabilities.none
  let defaultColor: ControllerColor? = nil
  func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }
  func parse(report _: Data, receivedAt _: MonotonicTimestamp) throws -> ControllerEvent? { nil }
}

private actor ScriptedUSBTransportProvider: USBTransportProvider {
  private let failuresBeforeSuccess: Int
  private var attempts = 0

  init(failuresBeforeSuccess: Int) { self.failuresBeforeSuccess = failuresBeforeSuccess }

  func devices() throws -> [USBTransportDevice] { [] }

  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) throws -> any USBTransportSession {
    attempts += 1
    if attempts <= failuresBeforeSuccess { throw USBTransportError.accessDenied }
    return StartupUSBTransportSession()
  }

  func openAttempts() -> Int { attempts }
}

private actor StartupUSBTransportSession: USBTransportSession {
  func controlTransfer(_ request: USBControlTransferRequest, timeout: UInt32) throws -> [UInt8] {
    throw USBTransportError.notSupported
  }

  var inputOwnership: HIDInputOwnership { .exclusive }
  func write(endpoint: UInt8, data: [UInt8], timeout: UInt32) throws -> Int { data.count }

  func read(endpoint: UInt8, length: Int, timeout: UInt32) throws -> [UInt8] {
    throw USBTransportError.timeout
  }
}

private actor SuspendedSuccessfulUSBTransportProvider: USBTransportProvider {
  private let session: ClosingUSBTransportSession
  private var startedOpen = false
  private var continuation: CheckedContinuation<Void, Never>?

  init(session: ClosingUSBTransportSession) { self.session = session }

  func devices() throws -> [USBTransportDevice] { [] }

  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession {
    startedOpen = true
    await withCheckedContinuation { continuation = $0 }
    return session
  }

  func hasStartedOpen() -> Bool { startedOpen }

  func resumeOpen() {
    continuation?.resume()
    continuation = nil
  }
}

private actor ClosingUSBTransportSession: USBTransportSession {
  func controlTransfer(_ request: USBControlTransferRequest, timeout: UInt32) throws -> [UInt8] {
    throw USBTransportError.notSupported
  }

  var inputOwnership: HIDInputOwnership { closes == 0 ? .exclusive : .unknown }
  private var closes = 0

  func write(endpoint: UInt8, data: [UInt8], timeout: UInt32) throws -> Int { data.count }

  func read(endpoint: UInt8, length: Int, timeout: UInt32) throws -> [UInt8] {
    throw USBTransportError.timeout
  }

  func close() { closes += 1 }

  func closeCount() -> Int { closes }
}

private final class StartupRecordingOutputDispatcher: OutputDispatcher,
  ControllerInputOwnershipListener, @unchecked Sendable
{
  var suppressOutput = false

  private let lock = NSLock()
  private var recordedActivations = 0
  private var recordedOwnership: [HIDInputOwnership] = []
  private var dispatchedOwnership: [HIDInputOwnership] = []

  var ownershipStates: [HIDInputOwnership] { lock.withLock { recordedOwnership } }
  var ownershipAtDispatch: [HIDInputOwnership] { lock.withLock { dispatchedOwnership } }

  func controllerInputOwnershipChanged(
    _ ownership: HIDInputOwnership,
    for identifier: DeviceIdentifier
  ) { lock.withLock { recordedOwnership.append(ownership) } }

  var activations: Int { lock.withLock { recordedActivations } }

  func dispatch(_: ControllerEvent, labels _: ControllerButtonLabels, from _: DeviceIdentifier) {}

  func activateOutput(for _: DeviceIdentifier) {
    lock.withLock {
      recordedActivations += 1
      dispatchedOwnership.append(recordedOwnership.last ?? .unknown)
    }
  }
}
