import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct USBLifecycleWriteTests {
  @Test
  func keepAliveKeepsItsIntervalWhileReadsBlockAndStopsWithTheRun() async {
    let driver = LifecycleWriteDriver(
      sessionPlan: DriverSessionPlan(usbKeepAliveIntervalNanoseconds: 20_000_000),
      keepAlive: [Self.write(endpoint: 0x03, bytes: [0xAA])]
    )
    let session = LifecycleUSBSession()
    let pipeline = Self.pipeline(driver: driver, session: session)

    await pipeline.start()
    // Reads never return, so every keep-alive comes from the keep-alive timer.
    #expect(await waitUntil { await session.writes.count >= 3 })
    await pipeline.stop()
    try? await Task.sleep(nanoseconds: 60_000_000)
    let countAfterStop = await session.writes.count
    try? await Task.sleep(nanoseconds: 150_000_000)

    #expect(await session.writes.count == countAfterStop)
    #expect(await session.readCount == 1)
    #expect(await session.writes.allSatisfy { $0 == .init(0x03, [0xAA], 2_000) })
  }

  @Test
  func handleChangeStopsConnectionWritesButKeepsTheConsumedStateChange() async {
    let driver = LifecycleWriteDriver(
      sessionPlan: DriverSessionPlan(requiresInputConnectionBeforeOutput: true),
      connection: [Self.write(endpoint: 0x02, bytes: [1]), Self.write(endpoint: 0x02, bytes: [2])]
    )
    let first = LifecycleUSBSession()
    let replacement = LifecycleUSBSession()
    let pipeline = Self.pipeline(driver: driver, session: first)
    await pipeline.activateForTesting()
    await pipeline.setUSBHandleForTesting(first)
    await first.setOnWrite { await pipeline.setUSBHandleForTesting(replacement) }
    driver.announce(.connected)

    _ = await pipeline.handleInputConnectionStateChangeIfNeeded()

    #expect(await pipeline.inputConnectionActive)
    #expect(await first.writes.map(\.bytes) == [[1]])
    #expect(await replacement.writes.isEmpty)
  }

  @Test
  func startupWritesUseTheirOwnDestinationAndTolerateOnlyTheirOwnRejection() async {
    let tolerated = PhysicalUSBOutputPacket(endpoint: 0x05, bytes: [0x10], timeoutMilliseconds: 1)
    let next = PhysicalUSBOutputPacket(endpoint: 0x06, bytes: [0x20], timeoutMilliseconds: 7)

    let toleratingDriver = LifecycleWriteDriver(startup: [
      .usb(tolerated, toleratesRejection: true), .usb(next),
    ])
    let toleratingSession = LifecycleUSBSession(rejections: [[0x10]: .notSupported])
    let toleratingPipeline = Self.pipeline(driver: toleratingDriver, session: toleratingSession)
    await toleratingPipeline.activateForTesting()
    await toleratingPipeline.setUSBHandleForTesting(toleratingSession)

    #expect(await toleratingPipeline.performUSBHandshake(handle: toleratingSession))
    #expect(await toleratingSession.writes == [.init(0x05, [0x10], 1), .init(0x06, [0x20], 7)])

    let strictDriver = LifecycleWriteDriver(startup: [.usb(tolerated), .usb(next)])
    let strictSession = LifecycleUSBSession(rejections: [[0x10]: .notSupported])
    let strictPipeline = Self.pipeline(driver: strictDriver, session: strictSession)
    await strictPipeline.activateForTesting()
    await strictPipeline.setUSBHandleForTesting(strictSession)

    #expect(!(await strictPipeline.performUSBHandshake(handle: strictSession)))
    #expect(await strictSession.writes == [.init(0x05, [0x10], 1)])
  }

  @Test
  func receiverSlotWhosePresenceInquiryTimesOutStillStarts() async {
    let inquiry: [UInt8] = [0x08, 0x00, 0x0F, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    let session = LifecycleUSBSession(rejections: [inquiry: .timeout])
    let pipeline = Self.pipeline(driver: XUSBDriver(isWirelessReceiver: true), session: session)
    await pipeline.activateForTesting()
    await pipeline.setUSBHandleForTesting(session)

    #expect(await pipeline.performUSBHandshake(handle: session))
    #expect(await session.writes == [.init(0x01, inquiry, 2_000)])
  }

  /// A controller that stayed attached through sleep can open but fail its startup writes as
  /// disconnected until its port is reset. The pipeline resets it once and keeps retrying.
  @Test
  func startupFailingAsDisconnectedResetsTheDeviceOnce() async {
    let driver = LifecycleWriteDriver(startup: [Self.write(endpoint: 0x02, bytes: [0x10])])
    let session = LifecycleUSBSession(rejections: [[0x10]: .disconnected])
    let provider = LifecycleUSBProvider(session: session)
    let pipeline = Self.pipeline(
      driver: driver,
      provider: provider,
      recoveryPolicy: USBPipelineRecoveryPolicy(
        openRetryDelays: [1],
        reconnectBaseDelayNanoseconds: 1_000_000,
        reconnectMaximumDelayNanoseconds: 1_000_000,
        accessContentionDelayNanoseconds: 1_000_000
      )
    )

    await pipeline.start()
    #expect(await waitUntil { await provider.openCount >= 3 })
    await pipeline.stop()

    #expect(await provider.resetCount == 1)
  }

  /// A startup that the device rejects for another reason does not reset the device.
  @Test
  func startupFailingForAnotherReasonDoesNotResetTheDevice() async {
    let driver = LifecycleWriteDriver(startup: [Self.write(endpoint: 0x02, bytes: [0x10])])
    let session = LifecycleUSBSession(rejections: [[0x10]: .inputOutput])
    let provider = LifecycleUSBProvider(session: session)
    let pipeline = Self.pipeline(driver: driver, provider: provider)
    await pipeline.activateForTesting()
    await pipeline.setUSBHandleForTesting(session)

    #expect(await !pipeline.performUSBHandshake(handle: session))
    await pipeline.resetUSBDeviceIfUnresponsive(Self.device, provider: provider)

    #expect(await provider.resetCount == 0)
  }

  private static func write(endpoint: UInt8, bytes: [UInt8]) -> PhysicalOutputWrite {
    .usb(PhysicalUSBOutputPacket(endpoint: endpoint, bytes: bytes, timeoutMilliseconds: 2_000))
  }

  private static let device = USBTransportDevice(
    route: .ioUSBHost,
    serviceID: 1,
    vendorID: 0x1532,
    productID: 0x0A15,
    locationID: 7
  )

  /// The pipeline's profile names endpoints 0x82/0x02, unlike the writes above.
  private static func pipeline(
    driver: sending any PhysicalProtocolDriver,
    session: LifecycleUSBSession
  ) -> DevicePipeline { pipeline(driver: driver, provider: LifecycleUSBProvider(session: session)) }

  private static func pipeline(
    driver: sending any PhysicalProtocolDriver,
    provider: LifecycleUSBProvider,
    recoveryPolicy: USBPipelineRecoveryPolicy = .standard
  ) -> DevicePipeline {
    DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 0x1532, productID: 0x0A15),
      transport: .usb(device: device),
      driver: driver,
      dispatcher: LoggingOutputDispatcher(),
      usbTransportProvider: provider,
      transportProfile: .gipDefault,
      usbRecoveryPolicy: recoveryPolicy
    )
  }

  private func waitUntil(
    timeoutNanoseconds: UInt64 = 5_000_000_000,
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

private final class LifecycleWriteDriver: PhysicalProtocolDriver, @unchecked Sendable {
  let capabilities = ControllerCapabilities(controls: ControlID.xboxLayout)
  let sessionPlan: DriverSessionPlan
  let outputCapabilities = PhysicalControllerOutputCapabilities.none
  let defaultColor: ControllerColor? = nil
  private let startup: [PhysicalOutputWrite]
  private let keepAlive: [PhysicalOutputWrite]
  private let connection: [PhysicalOutputWrite]
  private let lock = NSLock()
  private var pendingState: ControllerInputConnectionState?

  init(
    sessionPlan: DriverSessionPlan = DriverSessionPlan(),
    startup: [PhysicalOutputWrite] = [],
    keepAlive: [PhysicalOutputWrite] = [],
    connection: [PhysicalOutputWrite] = []
  ) {
    self.sessionPlan = sessionPlan
    self.startup = startup
    self.keepAlive = keepAlive
    self.connection = connection
  }

  func announce(_ state: ControllerInputConnectionState) { lock.withLock { pendingState = state } }

  func parse(report _: Data, receivedAt _: MonotonicTimestamp) throws -> ControllerEvent? { nil }

  func consumeInputConnectionStateChange() -> ControllerInputConnectionState? {
    lock.withLock {
      defer { pendingState = nil }
      return pendingState
    }
  }

  func startupWrites() -> [PhysicalOutputWrite] { startup }
  func keepAliveWrites() -> [PhysicalOutputWrite] { keepAlive }

  func inputConnectionWrites(for _: ControllerInputConnectionState) -> [PhysicalOutputWrite] {
    connection
  }
}

/// Records writes; its interrupt reads block until the session closes, like an idle controller.
private actor LifecycleUSBSession: USBTransportSession {
  struct Write: Equatable {
    let endpoint: UInt8
    let bytes: [UInt8]
    let timeout: UInt32

    init(_ endpoint: UInt8, _ bytes: [UInt8], _ timeout: UInt32) {
      self.endpoint = endpoint
      self.bytes = bytes
      self.timeout = timeout
    }
  }

  private(set) var writes: [Write] = []
  private(set) var readCount = 0
  private let rejections: [[UInt8]: USBTransportError]
  private var onWrite: (@Sendable () async -> Void)?
  private var isClosed = false
  private var blockedRead: CheckedContinuation<Void, Never>?

  init(rejections: [[UInt8]: USBTransportError] = [:]) { self.rejections = rejections }

  func setOnWrite(_ hook: @escaping @Sendable () async -> Void) { onWrite = hook }

  func write(endpoint: UInt8, data: [UInt8], timeout: UInt32) async throws -> Int {
    guard !isClosed else { throw USBTransportError.disconnected }
    writes.append(Write(endpoint, data, timeout))
    if let hook = onWrite {
      onWrite = nil
      await hook()
    }
    if let error = rejections[data] { throw error }
    return data.count
  }

  func read(endpoint _: UInt8, length _: Int, timeout _: UInt32) async throws -> [UInt8] {
    readCount += 1
    if !isClosed { await withCheckedContinuation { blockedRead = $0 } }
    throw USBTransportError.disconnected
  }

  func controlTransfer(_: USBControlTransferRequest, timeout _: UInt32) throws -> [UInt8] {
    throw USBTransportError.notSupported
  }

  func close() {
    isClosed = true
    blockedRead?.resume()
    blockedRead = nil
  }
}

private actor LifecycleUSBProvider: USBTransportProvider {
  private let session: LifecycleUSBSession
  private(set) var openCount = 0
  private(set) var resetCount = 0

  init(session: LifecycleUSBSession) { self.session = session }

  func devices() -> [USBTransportDevice] { [] }

  func open(_: USBTransportDevice, options _: USBTransportOpenOptions) -> any USBTransportSession {
    openCount += 1
    return session
  }

  func resetDevice(_: USBTransportDevice) { resetCount += 1 }
}
