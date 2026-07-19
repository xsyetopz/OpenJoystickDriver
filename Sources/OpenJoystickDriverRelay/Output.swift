import Foundation
import OpenJoystickDriverKit
import SwifterKit

/// Publishes normalized controller state through the SwifterKit DriverKit runtime.
public final class DriverKitOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  public static let unstableNotification = Notification.Name("OpenJoystickDriver.DriverKitUnstable")

  private let stateLock = NSLock()
  private let runtime: DriverKitRelayRuntime
  private let enableBridge: DriverKitStateBridge
  private let suppressionBridge: DriverKitStateBridge
  private let reportPipeline: DriverKitReportPipeline
  private var isSuppressed = false
  private var suppressionRevision: UInt64 = 0

  public var suppressOutput: Bool {
    get { stateLock.withLock { isSuppressed } }
    set {
      let revision = suppressionBridge.request(newValue)
      stateLock.withLock {
        isSuppressed = newValue
        suppressionRevision = revision
      }
    }
  }

  public init() {
    let driver = OpenJoystickRelayDriver()
    let runtime = DriverKitRelayRuntime(
      submitter: driver,
      host: SwifterRelayHost(driver: driver)
    )
    let pipeline = DriverKitReportPipeline(runtime: runtime)
    self.runtime = runtime
    self.reportPipeline = pipeline
    self.enableBridge = DriverKitStateBridge { enabled, revision in
      await runtime.setEnabled(enabled, revision: revision)
    }
    self.suppressionBridge = DriverKitStateBridge(preservesTrueEdges: true) {
      suppressed,
      revision in
      await pipeline.setSuppressed(suppressed, revision: revision)
    }
  }

  init(runtime: DriverKitRelayRuntime) {
    let pipeline = DriverKitReportPipeline(runtime: runtime)
    self.runtime = runtime
    self.reportPipeline = pipeline
    self.enableBridge = DriverKitStateBridge { enabled, revision in
      await runtime.setEnabled(enabled, revision: revision)
    }
    self.suppressionBridge = DriverKitStateBridge(preservesTrueEdges: true) {
      suppressed,
      revision in
      await pipeline.setSuppressed(suppressed, revision: revision)
    }
  }

  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    let suppression = stateLock.withLock { (isSuppressed, suppressionRevision) }
    await suppressionBridge.wait(untilApplied: suppression.1)
    guard !suppression.0 else { return }
    await reportPipeline.dispatch(events: events)
  }

  @discardableResult public func sendDiagnosticProbe(reportCount: Int = 26) async -> Int {
    let suppression = stateLock.withLock { (isSuppressed, suppressionRevision) }
    await suppressionBridge.wait(untilApplied: suppression.1)
    guard !suppression.0 else { return 0 }
    let reports = Self.diagnosticProbeReports(reportCount: reportCount).map {
      HIDReport(bytes: $0, type: .input)
    }
    return await reportPipeline.submit(reports: reports)
  }

  static func diagnosticProbeReports(reportCount: Int) -> [[UInt8]] {
    let boundedCount = min(max(1, reportCount), 100)
    let format = OJDGenericGamepadFormat()
    return (0..<boundedCount).map { index in
      let final = index == boundedCount - 1
      let buttons: UInt32 = index.isMultiple(of: 2) && !final ? 1 : 0
      return format.buildInputReport(from: VirtualGamepadState(buttons: buttons))
    }
  }

  public func outputStatsSnapshot() async -> ApplicationServiceDriverKitOutputStats {
    await runtime.statsSnapshot()
  }

  public func runtimeStatisticsSnapshot() async -> DriverKitRelayRuntimeStatistics? {
    await runtime.runtimeStatisticsSnapshot()
  }

  public func setEnabled(_ enabled: Bool) { enableBridge.request(enabled) }

  private func setEnabledAndWait(_ enabled: Bool) async {
    let revision = enableBridge.request(enabled)
    await enableBridge.wait(untilApplied: revision)
  }
}

extension DriverKitOutputDispatcher: VirtualControllerBackend {
  public var backendID: VirtualControllerBackendID { .driverKitHID }

  public var capabilities: VirtualControllerBackendCapabilities {
    VirtualControllerBackendCapabilities(
      isSystemWide: true,
      supportsMultiplePhysicalControllers: false,
      requiresEntitlement: true,
      isImplemented: true,
      publishesConsumerGamepad: false,
      notes: "Vendor-defined DriverKit integrity relay for self-test and diagnostics; "
        + "Compatibility IOHIDUserDevice publishes the consumer gamepad."
    )
  }

  public func startBackend() async -> VirtualControllerBackendStatus {
    await setEnabledAndWait(true)
    let connected = await runtime.waitUntilConnected()
    return VirtualControllerBackendStatus(
      id: backendID,
      isRunning: connected,
      detail: connected ? "connected" : "virtual HID runtime not found"
    )
  }

  public func stopBackend() async { await setEnabledAndWait(false) }

  public func backendStatus() -> VirtualControllerBackendStatus {
    let running = runtime.cachedConnectionState
    return VirtualControllerBackendStatus(
      id: backendID,
      isRunning: running,
      detail: running ? "connected" : "not connected"
    )
  }
}

struct DriverKitReportPipelineMetrics: Sendable, Equatable {
  let workerStarts: Int
  let maximumConcurrentWorkers: Int
  let pendingReportCapacity: Int
  let maximumPendingReports: Int
  let coalescedReports: Int
  let diagnosticCapacity: Int
  let maximumDiagnosticDepth: Int
  let rejectedDiagnostics: Int
}

actor DriverKitReportPipeline {
  private final class DiagnosticCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int, Never>?

    init(_ continuation: CheckedContinuation<Int, Never>) { self.continuation = continuation }

    func resume(returning value: Int) {
      lock.withLock {
        continuation?.resume(returning: value)
        continuation = nil
      }
    }
  }

  private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() { lock.withLock { cancelled = true } }
    func shouldContinue() -> Bool { lock.withLock { !cancelled } }
  }

  private struct DiagnosticWork {
    let id: UUID
    let reports: [HIDReport]
    let cancellation: CancellationFlag
    let completion: DiagnosticCompletion
  }

  private static let diagnosticCapacity = 4
  private let runtime: DriverKitRelayRuntime
  private let format: any VirtualGamepadReportFormat = OJDGenericGamepadFormat()
  private var pendingReport: HIDReport?
  private var diagnostics: [DiagnosticWork] = []
  private var inFlightDiagnosticID: UUID?
  private var inFlightDiagnosticCancellation: CancellationFlag?
  private var workerRunning = false
  private var workerStarts = 0
  private var activeWorkers = 0
  private var maximumConcurrentWorkers = 0
  private var maximumPendingReports = 0
  private var coalescedReports = 0
  private var maximumDiagnosticDepth = 0
  private var rejectedDiagnostics = 0
  private var preferDiagnostic = false
  private var suppressed = false
  private var suppressionRevision: UInt64 = 0
  private var buttons: UInt32 = 0
  private var leftStickX: Int16 = 0
  private var leftStickY: Int16 = 0
  private var rightStickX: Int16 = 0
  private var rightStickY: Int16 = 0
  private var leftTrigger: Int16 = 0
  private var rightTrigger: Int16 = 0
  private var hat: GamepadHIDDescriptor.Hat = .neutral

  init(runtime: DriverKitRelayRuntime) { self.runtime = runtime }

  func dispatch(events: [ControllerEvent]) {
    guard !suppressed else { return }
    events.forEach(apply)
    if pendingReport != nil { coalescedReports += 1 }
    pendingReport = HIDReport(bytes: primaryReport(), type: .input)
    maximumPendingReports = max(maximumPendingReports, 1)
    startWorkerIfNeeded()
  }

  func submit(reports: [HIDReport]) async -> Int {
    guard !suppressed else { return 0 }
    guard diagnostics.count < Self.diagnosticCapacity else {
      rejectedDiagnostics += 1
      return 0
    }
    let cancellation = CancellationFlag()
    let id = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { completion in
        diagnostics.append(
          DiagnosticWork(
            id: id,
            reports: reports,
            cancellation: cancellation,
            completion: DiagnosticCompletion(completion)
          )
        )
        maximumDiagnosticDepth = max(maximumDiagnosticDepth, diagnostics.count)
        startWorkerIfNeeded()
      }
    } onCancel: {
      cancellation.cancel()
      Task { await self.cancelDiagnostic(id) }
    }
  }

  func metrics() -> DriverKitReportPipelineMetrics {
    DriverKitReportPipelineMetrics(
      workerStarts: workerStarts,
      maximumConcurrentWorkers: maximumConcurrentWorkers,
      pendingReportCapacity: 1,
      maximumPendingReports: maximumPendingReports,
      coalescedReports: coalescedReports,
      diagnosticCapacity: Self.diagnosticCapacity,
      maximumDiagnosticDepth: maximumDiagnosticDepth,
      rejectedDiagnostics: rejectedDiagnostics
    )
  }

  func setSuppressed(_ value: Bool, revision: UInt64) async {
    guard revision >= suppressionRevision else { return }
    suppressionRevision = revision
    suppressed = value
    guard value else { return }

    pendingReport = nil
    let cancelledDiagnostics = diagnostics
    diagnostics.removeAll()
    cancelledDiagnostics.forEach { $0.completion.resume(returning: 0) }
    inFlightDiagnosticCancellation?.cancel()
    resetState()
    await runtime.invalidateSubmissions()
  }

  private func startWorkerIfNeeded() {
    guard !workerRunning else { return }
    workerRunning = true
    workerStarts += 1
    activeWorkers += 1
    maximumConcurrentWorkers = max(maximumConcurrentWorkers, activeWorkers)
    Task { await drain() }
  }

  private func drain() async {
    while true {
      if !diagnostics.isEmpty, pendingReport == nil || preferDiagnostic {
        let work = diagnostics.removeFirst()
        preferDiagnostic = false
        inFlightDiagnosticID = work.id
        inFlightDiagnosticCancellation = work.cancellation
        let delivered = await runtime.submit(
          work.reports,
          shouldContinue: work.cancellation.shouldContinue
        )
        inFlightDiagnosticID = nil
        inFlightDiagnosticCancellation = nil
        work.completion.resume(returning: delivered)
        continue
      }
      if let report = pendingReport {
        pendingReport = nil
        preferDiagnostic = true
        _ = await runtime.submit([report])
        continue
      }
      workerRunning = false
      activeWorkers -= 1
      return
    }
  }

  private func cancelDiagnostic(_ id: UUID) async {
    if let index = diagnostics.firstIndex(where: { $0.id == id }) {
      diagnostics.remove(at: index).completion.resume(returning: 0)
      return
    }
    if inFlightDiagnosticID == id {
      await runtime.invalidateSubmissions()
    }
  }

  private func apply(_ event: ControllerEvent) {
    switch event {
    case .buttonPressed(let button): if let bit = buttonBit(for: button) { buttons |= 1 << bit }
    case .buttonReleased(let button): if let bit = buttonBit(for: button) { buttons &= ~(1 << bit) }
    case .leftStickChanged(let x, let y):
      leftStickX = axis(x)
      leftStickY = axis(y)
    case .rightStickChanged(let x, let y):
      rightStickX = axis(x)
      rightStickY = axis(y)
    case .leftTriggerChanged(let value):
      leftTrigger = Int16(Swift.min(Swift.max(value, 0), 1) * 32_767)
    case .rightTriggerChanged(let value):
      rightTrigger = Int16(Swift.min(Swift.max(value, 0), 1) * 32_767)
    case .dpadChanged(let direction):
      hat = hatValue(for: direction)
      let mask: UInt32 = 0xF << 11
      buttons = (buttons & ~mask) | GamepadHIDDescriptor.dpadButtonBits(for: hat)
    }
  }

  private func resetState() {
    buttons = 0
    leftStickX = 0
    leftStickY = 0
    rightStickX = 0
    rightStickY = 0
    leftTrigger = 0
    rightTrigger = 0
    hat = .neutral
  }

  private func primaryReport() -> [UInt8] {
    format.buildInputReport(
      from: VirtualGamepadState(
        buttons: buttons,
        leftStickX: leftStickX,
        leftStickY: leftStickY,
        rightStickX: rightStickX,
        rightStickY: rightStickY,
        leftTrigger: leftTrigger,
        rightTrigger: rightTrigger,
        hat: hat
      )
    )
  }

  private func axis(_ value: Float) -> Int16 {
    let clamped = Swift.min(Swift.max(value, -1), 1)
    return abs(clamped) > 0.15 ? Int16(clamped * 32_767) : 0
  }

  private func buttonBit(for button: Button) -> UInt32? {
    switch button {
    case .a, .cross: 0
    case .b, .circle: 1
    case .x, .square: 2
    case .y, .triangle: 3
    case .leftBumper, .l1: 4
    case .rightBumper, .r1: 5
    case .leftStick: 6
    case .rightStick: 7
    case .start, .options: 8
    case .back: 9
    case .guide, .ps: 10
    case .dpadUp: 11
    case .dpadDown: 12
    case .dpadLeft: 13
    case .dpadRight: 14
    case .share, .genericButton1: 15
    case .l2Digital, .r2Digital, .touchpad, .genericButton2, .genericButton3, .genericButton4,
      .genericButton5, .genericButton6, .genericButton7, .genericButton8:
      nil
    }
  }

  private func hatValue(for direction: DpadDirection) -> GamepadHIDDescriptor.Hat {
    switch direction {
    case .neutral: .neutral
    case .north: .north
    case .northEast: .northEast
    case .east: .east
    case .southEast: .southEast
    case .south: .south
    case .southWest: .southWest
    case .west: .west
    case .northWest: .northWest
    }
  }
}
