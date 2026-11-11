import Foundation

@testable import OpenJoystickDriverKit

actor USBManagerResolutionProvider: USBTransportProvider {
  let device: USBTransportDevice
  let resolvedProfile: DeviceTransportProfile
  let physicalDevice: PhysicalDevice?
  let session = USBManagerResolutionSession()
  private(set) var options: USBTransportOpenOptions?
  private var didOpen = false
  private var openContinuation: CheckedContinuation<Void, Never>?
  private(set) var openCount = 0
  private(set) var resolutionCount = 0
  private var openWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private var resolutionWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private(set) var devicesCallCount = 0
  private var devicesWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private var pendingEnumerationFailures: [USBTransportError] = []
  private var resolutionSuspended = false
  private var suspendedResolutionContinuations:
    [CheckedContinuation<USBTransportResolution, Never>] = []

  init(
    device: USBTransportDevice,
    resolvedProfile: DeviceTransportProfile,
    physicalDevice: PhysicalDevice? = nil
  ) {
    self.device = device
    self.resolvedProfile = resolvedProfile
    self.physicalDevice = physicalDevice
  }

  private var currentDevices: [USBTransportDevice]?

  func devices() throws -> [USBTransportDevice] {
    devicesCallCount += 1
    signalWaiters(&devicesWaiters, count: devicesCallCount)
    if !pendingEnumerationFailures.isEmpty { throw pendingEnumerationFailures.removeFirst() }
    return currentDevices ?? [device]
  }

  func resolveTransport(
    for _: USBTransportDevice,
    configured _: DeviceTransportProfile
  ) async -> USBTransportResolution {
    resolutionCount += 1
    signalWaiters(&resolutionWaiters, count: resolutionCount)
    if resolutionSuspended {
      return await withCheckedContinuation { suspendedResolutionContinuations.append($0) }
    }
    return USBTransportResolution(profile: resolvedProfile, physicalDevice: physicalDevice)
  }

  func setDevices(_ devices: [USBTransportDevice]) { currentDevices = devices }

  func suspendResolutions() { resolutionSuspended = true }

  func resumeResolutions() {
    resolutionSuspended = false
    let resolution = USBTransportResolution(
      profile: resolvedProfile,
      physicalDevice: physicalDevice
    )
    for continuation in suspendedResolutionContinuations {
      continuation.resume(returning: resolution)
    }
    suspendedResolutionContinuations.removeAll()
  }

  func failNextEnumeration(_ error: USBTransportError) { pendingEnumerationFailures.append(error) }

  func open(
    _: USBTransportDevice,
    options: USBTransportOpenOptions
  ) -> any USBTransportSession {
    self.options = options
    didOpen = true
    openCount += 1
    signalWaiters(&openWaiters, count: openCount)
    openContinuation?.resume()
    openContinuation = nil
    return session
  }

  func waitForOpen() async {
    guard !didOpen else { return }
    await withCheckedContinuation { openContinuation = $0 }
  }

  func waitForOpenCount(_ count: Int) async {
    guard openCount < count else { return }
    await withCheckedContinuation { openWaiters.append((count, $0)) }
  }

  func waitForResolutionCount(_ count: Int) async {
    guard resolutionCount < count else { return }
    await withCheckedContinuation { resolutionWaiters.append((count, $0)) }
  }

  func waitForDevicesCallCount(_ count: Int) async {
    guard devicesCallCount < count else { return }
    await withCheckedContinuation { devicesWaiters.append((count, $0)) }
  }

  private func signalWaiters(_ waiters: inout [(Int, CheckedContinuation<Void, Never>)], count: Int)
  {
    let ready = waiters.filter { $0.0 <= count }
    waiters.removeAll { $0.0 <= count }
    for (_, continuation) in ready { continuation.resume() }
  }
}

actor USBManagerResolutionSession: USBTransportSession {
  func controlTransfer(_: USBControlTransferRequest, timeout _: UInt32) throws -> [UInt8] {
    throw USBTransportError.notSupported
  }

  private(set) var writes: [USBWriteRecord] = []
  private(set) var readEndpoints: [UInt8] = []
  private var didRead = false
  private var firstReadContinuation: CheckedContinuation<Void, Never>?
  private var handleStaysOpen = false
  private var neutralRumbleWritesSuspended = false
  private var didEnterNeutralRumbleWrite = false
  private var neutralRumbleWaiter: CheckedContinuation<Void, Never>?
  private var neutralRumbleWriteContinuation: CheckedContinuation<Int, Never>?

  func keepHandleOpen() { handleStaysOpen = true }

  func suspendNeutralRumbleWrites() { neutralRumbleWritesSuspended = true }

  func resumeNeutralRumbleWrites() {
    neutralRumbleWritesSuspended = false
    neutralRumbleWriteContinuation?.resume(returning: 8)
    neutralRumbleWriteContinuation = nil
  }

  func waitForNeutralRumbleWrite() async {
    guard !didEnterNeutralRumbleWrite else { return }
    await withCheckedContinuation { neutralRumbleWaiter = $0 }
  }

  func write(endpoint: UInt8, data: [UInt8], timeout _: UInt32) async -> Int {
    writes.append(USBWriteRecord(endpoint: endpoint, data: data))
    if data == [0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00], neutralRumbleWritesSuspended {
      didEnterNeutralRumbleWrite = true
      neutralRumbleWaiter?.resume()
      neutralRumbleWaiter = nil
      return await withCheckedContinuation { neutralRumbleWriteContinuation = $0 }
    }
    return data.count
  }

  func read(endpoint: UInt8, length _: Int, timeout _: UInt32) throws -> [UInt8] {
    readEndpoints.append(endpoint)
    if !didRead {
      didRead = true
      firstReadContinuation?.resume()
      firstReadContinuation = nil
    }
    if handleStaysOpen { throw USBTransportError.timeout }
    throw USBTransportError.disconnected
  }

  func waitForFirstRead() async {
    guard !didRead else { return }
    await withCheckedContinuation { firstReadContinuation = $0 }
  }
}
