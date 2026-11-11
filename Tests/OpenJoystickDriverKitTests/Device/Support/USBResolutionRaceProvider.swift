import Foundation

@testable import OpenJoystickDriverKit

actor USBResolutionRaceProvider: USBTransportProvider {
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

  func resolveTransport(
    for _: USBTransportDevice,
    configured: DeviceTransportProfile
  ) async -> USBTransportResolution {
    resolutionCount += 1
    signalWaiters(&resolutionWaiters, count: resolutionCount)
    if resolutionSuspended { await withCheckedContinuation { resolutionContinuations.append($0) } }
    return USBTransportResolution(profile: configured)
  }

  func open(
    _: USBTransportDevice,
    options _: USBTransportOpenOptions
  ) -> any USBTransportSession {
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
