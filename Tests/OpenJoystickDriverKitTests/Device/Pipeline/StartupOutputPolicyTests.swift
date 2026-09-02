import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct USBStartupOutputPolicyTests {
  @Test func defersVirtualOutputUntilThePhysicalUSBSessionOpens() async {
    let identifier = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let provider = ScriptedUSBTransportProvider(failuresBeforeSuccess: .max)
    let dispatcher = StartupRecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(device: Self.device),
      parser: StartupInputParser(),
      dispatcher: dispatcher,
      usbTransportProvider: provider,
      usbRecoveryPolicy: Self.fastRecoveryPolicy
    )

    let startTask = Task { await pipeline.start() }
    let retried = await waitUntil { await provider.openAttempts() >= 4 }

    #expect(retried)
    #expect(dispatcher.dispatchCount == 0)
    await pipeline.stop()
    await startTask.value
  }

  @Test func publishesVirtualOutputAfterARecoveredPhysicalUSBHandshake() async {
    let identifier = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let provider = ScriptedUSBTransportProvider(failuresBeforeSuccess: 3)
    let dispatcher = StartupRecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(device: Self.device),
      parser: StartupInputParser(),
      dispatcher: dispatcher,
      usbTransportProvider: provider,
      usbRecoveryPolicy: Self.fastRecoveryPolicy
    )

    let startTask = Task { await pipeline.start() }
    let published = await waitUntil { dispatcher.dispatchCount == 1 }

    #expect(published)
    #expect(await provider.openAttempts() == 4)
    #expect(dispatcher.batches == [[]])
    await pipeline.stop()
    await startTask.value
  }

  @Test func recoveryBackoffIsBounded() {
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

  @Test func accessContentionSkipsWastefulImmediateOpenRetries() async {
    let provider = ScriptedUSBTransportProvider(failuresBeforeSuccess: .max)
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 0x3537, productID: 0x1010),
      transport: .usb(device: Self.device),
      parser: StartupInputParser(),
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

  @Test func stopWhileOpenIsSuspendedCannotPublishOrOrphanVirtualOutput() async {
    let session = ClosingUSBTransportSession()
    let provider = SuspendedSuccessfulUSBTransportProvider(session: session)
    let dispatcher = StartupRecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 0x3537, productID: 0x1010),
      transport: .usb(device: Self.device),
      parser: StartupInputParser(),
      dispatcher: dispatcher,
      usbTransportProvider: provider,
      usbRecoveryPolicy: Self.fastRecoveryPolicy
    )

    let startTask = Task { await pipeline.start() }
    #expect(await waitUntil { await provider.hasStartedOpen() })

    await pipeline.stop()
    await provider.resumeOpen()
    await startTask.value

    #expect(dispatcher.dispatchCount == 0)
    #expect(await session.closeCount() == 1)
  }

  @Test func ignoresIOErrorForXbox360RingLED() {
    let parser = Xbox360Parser()
    let error = USBTransportError.inputOutput

    #expect(
      isIgnorableUSBStartupOutputError(parser: parser, packet: [0x01, 0x03, 0x06], error: error)
    )
  }

  @Test func ignoresUnsupportedErrorForXbox360RingLED() {
    let parser = Xbox360Parser()

    #expect(
      isIgnorableUSBStartupOutputError(
        parser: parser,
        packet: [0x01, 0x03, 0x06],
        error: .notSupported
      )
    )
  }

  @Test func ignoresNotFoundErrorForXbox360RingLED() {
    let parser = Xbox360Parser()

    #expect(
      isIgnorableUSBStartupOutputError(parser: parser, packet: [0x01, 0x03, 0x06], error: .notFound)
    )
  }

  @Test func preservesOtherXbox360StartupOutputFailures() {
    let parser = Xbox360Parser()
    let errors: [USBTransportError] = [
      .disconnected, .accessDenied, .timeout, .platform(code: 1, message: "unexpected")
    ]

    for error in errors {
      #expect(
        !isIgnorableUSBStartupOutputError(parser: parser, packet: [0x01, 0x03, 0x06], error: error)
      )
    }
  }

  @Test func preservesNotFoundForOtherStartupPacketsAndParsers() {
    let parser = Xbox360Parser()
    let genericParser = GenericHIDParser(identifier: DeviceIdentifier(vendorID: 1, productID: 2))

    #expect(
      !isIgnorableUSBStartupOutputError(parser: parser, packet: [0x00, 0x01], error: .notFound)
    )
    #expect(
      !isIgnorableUSBStartupOutputError(
        parser: genericParser,
        packet: [0x01, 0x03, 0x06],
        error: .notFound
      )
    )
  }

  @Test func preservesIOErrorForOtherStartupPacketsAndParsers() {
    let parser = Xbox360Parser()
    let genericParser = GenericHIDParser(identifier: DeviceIdentifier(vendorID: 1, productID: 2))
    let error = USBTransportError.inputOutput

    #expect(!isIgnorableUSBStartupOutputError(parser: parser, packet: [0x00, 0x01], error: error))
    #expect(
      !isIgnorableUSBStartupOutputError(
        parser: genericParser,
        packet: [0x01, 0x03, 0x06],
        error: error
      )
    )
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
    timeoutNanoseconds: UInt64 = 1_000_000_000,
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

private final class StartupInputParser: InputParser, @unchecked Sendable {
  func performHandshake(handle: (any USBTransportSession)?) async throws { await Task.yield() }
  func parse(data: Data) throws -> [ControllerEvent] { [] }
}

private actor ScriptedUSBTransportProvider: USBTransportProvider {
  private let failuresBeforeSuccess: Int
  private var attempts = 0

  init(failuresBeforeSuccess: Int) { self.failuresBeforeSuccess = failuresBeforeSuccess }

  func devices() throws -> [USBTransportDevice] { [] }

  func open(_ device: USBTransportDevice, options: USBTransportOpenOptions) throws
    -> any USBTransportSession
  {
    attempts += 1
    if attempts <= failuresBeforeSuccess { throw USBTransportError.accessDenied }
    return StartupUSBTransportSession()
  }

  func openAttempts() -> Int { attempts }
}

private actor StartupUSBTransportSession: USBTransportSession {
  func writeInterruptPacket(endpoint: UInt8, data: [UInt8], timeout: UInt32) throws -> Int {
    data.count
  }

  func readInterruptPacket(endpoint: UInt8, length: Int, timeout: UInt32) throws -> [UInt8] {
    throw USBTransportError.timeout
  }
}

private actor SuspendedSuccessfulUSBTransportProvider: USBTransportProvider {
  private let session: ClosingUSBTransportSession
  private var startedOpen = false
  private var continuation: CheckedContinuation<Void, Never>?

  init(session: ClosingUSBTransportSession) { self.session = session }

  func devices() throws -> [USBTransportDevice] { [] }

  func open(_ device: USBTransportDevice, options: USBTransportOpenOptions) async throws
    -> any USBTransportSession
  {
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
  private var closes = 0

  func writeInterruptPacket(endpoint: UInt8, data: [UInt8], timeout: UInt32) throws -> Int {
    data.count
  }

  func readInterruptPacket(endpoint: UInt8, length: Int, timeout: UInt32) throws -> [UInt8] {
    throw USBTransportError.timeout
  }

  func close() { closes += 1 }

  func closeCount() -> Int { closes }
}

private final class StartupRecordingOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  var suppressOutput = false

  private let lock = NSLock()
  private var recordedBatches: [[ControllerEvent]] = []

  var batches: [[ControllerEvent]] { lock.withLock { recordedBatches } }
  var dispatchCount: Int { lock.withLock { recordedBatches.count } }

  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) {
    lock.withLock { recordedBatches.append(events) }
  }
}
