import Foundation

@testable import OpenJoystickDriverKit

actor RecoveryUSBProvider: USBTransportProvider {
  private var sessions: [RecoveryUSBSession]
  private var listedDevices: [USBTransportDevice]
  private(set) var openCount = 0
  private(set) var openedDevices: [USBTransportDevice] = []
  private(set) var resolutionGateReached = false
  private var shouldGateNextResolution = false
  private var resolutionGateContinuation: CheckedContinuation<Void, Never>?

  init(sessions: [RecoveryUSBSession], devices: [USBTransportDevice] = []) {
    self.sessions = sessions
    listedDevices = devices
  }

  func devices() -> [USBTransportDevice] { listedDevices }

  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) throws -> any USBTransportSession {
    openCount += 1
    openedDevices.append(device)
    guard !sessions.isEmpty else { throw USBTransportError.notFound }
    return sessions.removeFirst()
  }

  func resolveTransport(
    for _: USBTransportDevice,
    configured: DeviceTransportProfile
  ) async -> USBTransportResolution {
    if shouldGateNextResolution {
      shouldGateNextResolution = false
      resolutionGateReached = true
      await withCheckedContinuation { resolutionGateContinuation = $0 }
    }
    return USBTransportResolution(profile: configured)
  }

  func gateNextResolution() { shouldGateNextResolution = true }

  func setDevices(_ devices: [USBTransportDevice]) { listedDevices = devices }

  func releaseResolutionGate() {
    resolutionGateContinuation?.resume()
    resolutionGateContinuation = nil
  }
}

actor RecoveryUSBSession: USBTransportSession {
  func controlTransfer(_ request: USBControlTransferRequest, timeout: UInt32) throws -> [UInt8] {
    throw USBTransportError.notSupported
  }

  let readError: USBTransportError
  private var readResults: [Result<[UInt8], USBTransportError>]
  private(set) var closeCount = 0
  private(set) var writes: [[UInt8]] = []
  private(set) var writeEndpoints: [UInt8] = []
  private(set) var readCount = 0
  var writeCount: Int { writes.count }
  var inputOwnership: HIDInputOwnership { closeCount == 0 ? .exclusive : .unknown }

  init(readError: USBTransportError) {
    self.readError = readError
    readResults = []
  }

  init(readResults: [Result<[UInt8], USBTransportError>], readError: USBTransportError) {
    self.readResults = readResults
    self.readError = readError
  }

  func write(endpoint: UInt8, data: [UInt8], timeout: UInt32) throws -> Int {
    guard closeCount == 0 else { throw USBTransportError.disconnected }
    writes.append(data)
    writeEndpoints.append(endpoint)
    return data.count
  }

  func read(endpoint: UInt8, length: Int, timeout: UInt32) throws -> [UInt8] {
    readCount += 1
    if !readResults.isEmpty {
      switch readResults.removeFirst() {
      case .success(let bytes): return bytes
      case .failure(let error): throw error
      }
    }
    throw readError
  }

  func close() {
    guard closeCount == 0 else { return }
    closeCount = 1
  }
}
