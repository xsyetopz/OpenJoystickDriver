import Foundation
import IOKit

@testable import OpenJoystickDriverKit

actor ScriptedHIDAccessBackend: HIDAccessBackend {
  private let delaysFirstStream: Bool
  private let closesSessionWhenStreamEnds: Bool
  private let session = ScriptedHIDSession()
  private var attempts = 0
  private var connectionSnapshots: [HIDDeviceConnectionSnapshot]? = []
  private var outputReportsEnabled = false
  private var outputReports: [PhysicalHIDOutputReport] = []
  private var outputReportConnectionIDs: [UUID] = []
  private var featureReportsEnabled = false
  private var featureReports: [PhysicalHIDOutputReport] = []
  private var featureReportTargets: [UUID?] = []
  private var featureReads = 0
  private var featureReadReportIDs: [UInt8] = []
  private var featureReadTargets: [UUID?] = []
  private var rejectedReports: [PhysicalHIDOutputReport] = []
  private var failingOutputReportCount = 0
  private var neutralMotorOutputGate: (started: StartupTestGate, release: StartupTestGate)?
  private var streams: [Int: AsyncStream<HIDDeviceEvent>] = [:]
  private var continuations: [Int: AsyncStream<HIDDeviceEvent>.Continuation] = [:]
  private var relays: [Int: ScriptedEventRelay] = [:]
  private var delayedFirstStream: CheckedContinuation<AsyncStream<HIDDeviceEvent>, Never>?
  private var attemptWaiters: [(attempt: Int, continuation: CheckedContinuation<Void, Never>)] = []

  /// `closesSessionWhenStreamEnds` models the IOHID backend, which closes its devices and rejects
  /// reports once the detection stream's consumer ends.
  init(delaysFirstStream: Bool = false, closesSessionWhenStreamEnds: Bool = false) {
    self.delaysFirstStream = delaysFirstStream
    self.closesSessionWhenStreamEnds = closesSessionWhenStreamEnds
  }

  func deviceEvents() async -> AsyncStream<HIDDeviceEvent> {
    attempts += 1
    let attempt = attempts
    let (source, continuation) = AsyncStream<HIDDeviceEvent>.makeStream()
    if closesSessionWhenStreamEnds {
      continuation.onTermination = { [session] _ in session.close() }
    }
    let relay = ScriptedEventRelay(source)
    let stream = AsyncStream<HIDDeviceEvent> { await relay.next() }
    relays[attempt] = relay
    streams[attempt] = stream
    continuations[attempt] = continuation
    let ready = attemptWaiters.filter { $0.attempt <= attempt }
    attemptWaiters.removeAll { $0.attempt <= attempt }
    for waiter in ready { waiter.continuation.resume() }
    guard delaysFirstStream, attempt == 1 else { return stream }
    return await withCheckedContinuation { delayedFirstStream = $0 }
  }

  func currentConnectionSnapshots() -> [HIDDeviceConnectionSnapshot]? { connectionSnapshots }

  func setOutputReport(
    address _: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    guard outputReportsEnabled, !rejectedReports.contains(report), !failsOutputReport() else {
      return .unavailable
    }
    outputReports.append(report)
    if isNeutralMotorReport(report), let gate = neutralMotorOutputGate {
      neutralMotorOutputGate = nil
      await gate.started.open()
      await gate.release.wait()
    }
    return .success(())
  }

  func setOutputReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    guard connectionSnapshots?.contains(where: { $0.connection == connection }) == true,
      outputReportsEnabled, !failsOutputReport()
    else { return .unavailable }
    outputReportConnectionIDs.append(connection.connectionID)
    outputReports.append(report)
    if isNeutralMotorReport(report), let gate = neutralMotorOutputGate {
      neutralMotorOutputGate = nil
      await gate.started.open()
      await gate.release.wait()
    }
    return .success(())
  }

  func setFeatureReport(
    address _: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> {
    guard featureReportsEnabled, !session.isClosed, !rejectedReports.contains(report) else {
      return .unavailable
    }
    featureReports.append(report)
    featureReportTargets.append(nil)
    return .success(())
  }

  func setFeatureReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> {
    guard connectionSnapshots?.contains(where: { $0.connection == connection }) == true,
      !session.isClosed, !rejectedReports.contains(report)
    else { return .unavailable }
    featureReports.append(report)
    featureReportTargets.append(connection.connectionID)
    return .success(())
  }

  func getFeatureReport(
    address _: ControllerConnectionAddress,
    request: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> {
    featureReads += 1
    featureReadReportIDs.append(request.reportID)
    featureReadTargets.append(nil)
    return .unavailable
  }

  func getFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> {
    featureReads += 1
    featureReadReportIDs.append(request.reportID)
    featureReadTargets.append(connection.connectionID)
    return .unavailable
  }

  func releaseInputClaim(address _: ControllerConnectionAddress) -> PhysicalHIDClaimResult {
    .unavailable
  }

  func reacquireInputClaim(address _: ControllerConnectionAddress) -> PhysicalHIDClaimResult {
    .unavailable
  }

  func retryInputClaim(address _: ControllerConnectionAddress) {}

  func routeElementValues(connection _: HIDDeviceConnection) {}

  func attemptCount() -> Int { attempts }

  /// Returns once `deviceEvents()` has been called at least `attempt` times.
  func waitForAttempt(_ attempt: Int) async {
    guard attempts < attempt else { return }
    await withCheckedContinuation { attemptWaiters.append((attempt, $0)) }
  }

  func isSessionClosed() -> Bool { session.isClosed }

  func enableOutputReports() { outputReportsEnabled = true }

  func enableFeatureReports() { featureReportsEnabled = true }

  /// Location-routed output writes and all feature writes of `report` fail without being
  /// recorded.
  func reject(_ report: PhysicalHIDOutputReport) { rejectedReports.append(report) }

  func disableOutputReports() { outputReportsEnabled = false }

  /// The next `count` output writes fail on either route without being recorded.
  func failNextOutputReports(_ count: Int) { failingOutputReportCount = count }

  private func failsOutputReport() -> Bool {
    guard failingOutputReportCount > 0 else { return false }
    failingOutputReportCount -= 1
    return true
  }

  func clearOutputReports() { outputReports.removeAll() }

  func blockNextNeutralMotorOutput(started: StartupTestGate, release: StartupTestGate) {
    neutralMotorOutputGate = (started, release)
  }

  func recordedOutputReports() -> [PhysicalHIDOutputReport] { outputReports }

  func recordedOutputReportConnectionIDs() -> [UUID] { outputReportConnectionIDs }

  func recordedFeatureReports() -> [PhysicalHIDOutputReport] { featureReports }

  func recordedFeatureReportTargets() -> [UUID?] { featureReportTargets }

  func recordedFeatureReadCount() -> Int { featureReads }

  func recordedFeatureReadReportIDs() -> [UInt8] { featureReadReportIDs }

  /// The connection each feature read targeted; nil for a location-routed read.
  func recordedFeatureReadTargets() -> [UUID?] { featureReadTargets }

  func setConnectionSnapshots(_ snapshots: [HIDDeviceConnectionSnapshot]?) {
    connectionSnapshots = snapshots
  }

  func yield(_ event: HIDDeviceEvent, attempt: Int) {
    relays[attempt]?.willYield()
    continuations[attempt]?.yield(event)
  }

  /// Returns once the consumer of the stream of attempt `attempt` has taken every yielded event.
  ///
  /// The consumer has also asked for the next one.
  func waitUntilConsumed(attempt: Int) async {
    await relays[attempt]?.waitUntilConsumed()
  }

  func fail(_ failure: PhysicalHIDFailure, attempt: Int) {
    relays[attempt]?.willYield()
    continuations[attempt]?.yield(.accessFailure(failure))
    continuations[attempt]?.finish()
  }

  func finish(attempt: Int) { continuations[attempt]?.finish() }

  func releaseFirstStream() {
    guard let delayedFirstStream, let stream = streams[1] else { return }
    self.delayedFirstStream = nil
    delayedFirstStream.resume(returning: stream)
  }

  private func isNeutralMotorReport(_ report: PhysicalHIDOutputReport) -> Bool {
    report.reportID == 0x11 && report.bytes.count > 7 && report.bytes[3] == 0x01
      && report.bytes[6] == 0 && report.bytes[7] == 0
  }
}

/// Hands a stream's events to its consumer and counts what the consumer asked for, so a test can
/// tell that the consumer has taken every event yielded so far.
private final class ScriptedEventRelay: @unchecked Sendable {
  private var iterator: AsyncStream<HIDDeviceEvent>.AsyncIterator
  private let lock = NSLock()
  private var yielded = 0
  private var requests = 0
  private var waiters: [CheckedContinuation<Void, Never>] = []

  init(_ source: AsyncStream<HIDDeviceEvent>) { iterator = source.makeAsyncIterator() }

  func willYield() { lock.withLock { yielded += 1 } }

  /// Called by the single consumer of the stream.
  func next() async -> HIDDeviceEvent? {
    let ready: [CheckedContinuation<Void, Never>] = lock.withLock {
      requests += 1
      guard requests > yielded else { return [] }
      defer { waiters.removeAll() }
      return waiters
    }
    for waiter in ready { waiter.resume() }
    return await iterator.next()
  }

  func waitUntilConsumed() async {
    await withCheckedContinuation { continuation in
      let consumed = lock.withLock {
        guard requests <= yielded else { return true }
        waiters.append(continuation)
        return false
      }
      if consumed { continuation.resume() }
    }
  }
}

private final class ScriptedHIDSession: @unchecked Sendable {
  private let lock = NSLock()
  private var closed = false

  var isClosed: Bool { lock.withLock { closed } }

  func close() { lock.withLock { closed = true } }
}
