import Foundation
import OpenJoystickDriverKit
import SwifterKit

protocol DriverKitRelayHosting: Sendable {
  func start() async throws -> String
  func run() async throws
  func stop() async
}

protocol DriverKitRelaySubmitting: Sendable {
  func submit(_ report: HIDReport) async throws
  func statistics() async throws -> HIDRuntimeStatistics
}

actor SwifterRelayHost: DriverKitRelayHosting {
  private let host: DriverHost<OpenJoystickRelayDriver>

  init(driver: OpenJoystickRelayDriver) { self.host = DriverHost(driver: driver) }

  func start() async throws -> String {
    let service = try await host.start()
    return "connected \(service.name)|\(service.id)"
  }

  func run() async throws { try await host.runEvents() }
  func stop() async { await host.stop() }
}

public struct DriverKitRelayRuntimeStatistics: Sendable, Equatable {
  public let inputReportAttempts: UInt64
  public let inputReportSuccesses: UInt64
  public let inputReportFailures: UInt64
}

private final class ConnectionSnapshot: @unchecked Sendable {
  private let lock = NSLock()
  private var connected = false

  func update(_ value: Bool) { lock.withLock { connected = value } }
  func read() -> Bool { lock.withLock { connected } }
}

actor DriverKitRelayRuntime {
  private let submitter: any DriverKitRelaySubmitting
  private let host: any DriverKitRelayHosting
  private let connectionSnapshot = ConnectionSnapshot()
  private var supervisor: Task<Void, Never>?
  private var supervisorGeneration: UInt64 = 0
  private var shutdownTask: Task<Void, Never>?
  private var shutdownGeneration: UInt64 = 0
  private var enabled = true
  private var enableRevision: UInt64 = 0
  private var submissionGeneration: UInt64 = 0
  private var restartRequestedForSupervisor: UInt64?
  private var connectionAttempts = 0
  private var connectionSuccesses = 0
  private var connectionFailures = 0
  private var submissionAttempts = 0
  private var submissionSuccesses = 0
  private var submissionFailures = 0
  private var lastSubmissionErrorHex: String?
  private var lastConnectionErrorHex: String?
  private var lastDiscoverySummary: String?
  private var failureTimes: [UInt64] = []
  private var lastUnstablePost: UInt64 = 0

  nonisolated var cachedConnectionState: Bool { connectionSnapshot.read() }
  var isConnected: Bool { connectionSnapshot.read() }
  var isEnabled: Bool { enabled }

  init(submitter: any DriverKitRelaySubmitting, host: any DriverKitRelayHosting) {
    self.submitter = submitter
    self.host = host
  }

  func setEnabled(_ value: Bool, revision: UInt64) async {
    guard revision >= enableRevision else { return }
    enableRevision = revision
    enabled = value
    if value {
      launchSupervisor()
      return
    }

    submissionGeneration &+= 1
    restartRequestedForSupervisor = nil
    let generation: UInt64
    if shutdownTask == nil {
      let previousSupervisor = supervisor
      supervisor = nil
      previousSupervisor?.cancel()
      shutdownGeneration &+= 1
      shutdownTask = Task { await previousSupervisor?.value }
    }
    generation = shutdownGeneration
    await shutdownTask?.value
    guard shutdownGeneration == generation, shutdownTask != nil else { return }
    shutdownTask = nil
    connectionSnapshot.update(false)
    if enabled { launchSupervisor() }
  }

  func waitUntilConnected() async -> Bool {
    launchSupervisor()
    for _ in 0..<25 {
      if connectionSnapshot.read() { return true }
      if !enabled { return false }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return connectionSnapshot.read()
  }

  func invalidateSubmissions() { submissionGeneration &+= 1 }

  @discardableResult func submit(
    _ reports: [HIDReport],
    shouldContinue: @Sendable () -> Bool = { true }
  ) async -> Int {
    guard enabled, !reports.isEmpty else { return 0 }
    let generation = submissionGeneration
    launchSupervisor()
    guard await waitUntilConnected(), submissionIsActive(generation) else { return 0 }

    var delivered = 0
    for report in reports {
      guard submissionIsActive(generation), shouldContinue() else { break }
      increment(&submissionAttempts)
      do {
        try await submitter.submit(report)
        increment(&submissionSuccesses)
        delivered += 1
      } catch {
        increment(&submissionFailures)
        lastSubmissionErrorHex = Self.platformErrorHex(error)
        lastDiscoverySummary = String("submission error: \(error)".prefix(500))
        recordUnstableFailure()
        if submissionIsActive(generation), shouldContinue() {
          restartRequestedForSupervisor = supervisorGeneration
          await host.stop()
        }
        break
      }
    }
    return delivered
  }

  func runtimeStatisticsSnapshot() async -> DriverKitRelayRuntimeStatistics? {
    guard enabled, connectionSnapshot.read() else { return nil }
    do {
      let statistics = try await submitter.statistics()
      return DriverKitRelayRuntimeStatistics(
        inputReportAttempts: statistics.inputReportAttempts,
        inputReportSuccesses: statistics.inputReportSuccesses,
        inputReportFailures: statistics.inputReportFailures
      )
    } catch { return nil }
  }

  func statsSnapshot() -> ApplicationServiceDriverKitOutputStats {
    ApplicationServiceDriverKitOutputStats(
      attempts: submissionAttempts,
      successes: submissionSuccesses,
      failures: submissionFailures,
      lastErrorHex: lastSubmissionErrorHex,
      connectionAttempts: connectionAttempts,
      connectionSuccesses: connectionSuccesses,
      connectionFailures: connectionFailures,
      lastConnectionErrorHex: lastConnectionErrorHex,
      lastDiscoverySummary: lastDiscoverySummary
    )
  }

  private func submissionIsActive(_ generation: UInt64) -> Bool {
    enabled && generation == submissionGeneration && !Task.isCancelled
  }

  private func launchSupervisor() {
    guard enabled, shutdownTask == nil, supervisor == nil else { return }
    supervisorGeneration &+= 1
    let generation = supervisorGeneration
    supervisor = Task { await supervise(generation: generation) }
  }

  private func supervise(generation: UInt64) async {
    var backoff: UInt64 = 250_000_000
    defer {
      connectionSnapshot.update(false)
      supervisor = nil
    }

    while enabled, !Task.isCancelled {
      increment(&connectionAttempts)
      do {
        let summary = try await host.start()
        increment(&connectionSuccesses)
        lastDiscoverySummary = String(summary.prefix(500))
        connectionSnapshot.update(true)
        backoff = 250_000_000
        try await host.run()
        if restartRequestedForSupervisor == generation {
          restartRequestedForSupervisor = nil
        } else if enabled, !Task.isCancelled {
          recordConnectionFailure(DriverKitRelayError.connectionEnded)
        }
      } catch is CancellationError { break } catch {
        if restartRequestedForSupervisor == generation {
          restartRequestedForSupervisor = nil
        } else if enabled, !Task.isCancelled {
          recordConnectionFailure(error)
        }
      }

      connectionSnapshot.update(false)
      await host.stop()
      guard enabled, !Task.isCancelled else { break }
      do { try await Task.sleep(nanoseconds: backoff) } catch { break }
      backoff = min(backoff &* 2, 5_000_000_000)
    }
    await host.stop()
  }

  private func recordConnectionFailure(_ error: any Error) {
    increment(&connectionFailures)
    lastConnectionErrorHex = Self.platformErrorHex(error)
    lastDiscoverySummary = String("runtime error: \(error)".prefix(500))
    recordUnstableFailure()
  }

  private func recordUnstableFailure() {
    let now = DispatchTime.now().uptimeNanoseconds
    failureTimes.append(now)
    if failureTimes.count > 512 { failureTimes.removeFirst(failureTimes.count - 512) }
    let cutoff = now > 5_000_000_000 ? now - 5_000_000_000 : 0
    failureTimes.removeAll { $0 < cutoff }
    if failureTimes.count >= 20, now - lastUnstablePost > 10_000_000_000 {
      lastUnstablePost = now
      NotificationCenter.default.post(
        name: DriverKitOutputDispatcher.unstableNotification,
        object: nil
      )
    }
  }

  private static func platformErrorHex(_ error: any Error) -> String? {
    guard let driverKitError = error as? DriverKitError,
      case .ioReturn(let value) = driverKitError.kind
    else { return nil }
    return String(format: "0x%08x", UInt32(bitPattern: value))
  }

  private func increment(_ value: inout Int) { if value < Int.max { value += 1 } }
}

private enum DriverKitRelayError: Error { case connectionEnded }
