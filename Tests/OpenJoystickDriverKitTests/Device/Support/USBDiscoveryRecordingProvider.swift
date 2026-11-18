import Foundation

@testable import OpenJoystickDriverKit

actor USBDiscoveryRecordingProvider: USBTransportProvider {
  private var currentDevices: [USBTransportDevice]
  private let physicalDevice: PhysicalDevice?
  private(set) var resolutionCount = 0
  private(set) var observationResolutionCount = 0

  init(devices: [USBTransportDevice], physicalDevice: PhysicalDevice? = nil) {
    currentDevices = devices
    self.physicalDevice = physicalDevice
  }

  func devices() -> [USBTransportDevice] { currentDevices }

  func setDevices(_ devices: [USBTransportDevice]) { currentDevices = devices }

  func resolveTransport(
    for _: USBTransportDevice,
    configured: DeviceTransportProfile
  ) -> USBTransportResolution {
    resolutionCount += 1
    if physicalDevice != nil { observationResolutionCount += 1 }
    return USBTransportResolution(profile: configured, physicalDevice: physicalDevice)
  }

  func open(
    _: USBTransportDevice,
    options _: USBTransportOpenOptions
  ) -> any USBTransportSession { USBDiscoveryRecordingSession() }
}

final class USBDiscoveryRecordingSession: USBTransportSession, @unchecked Sendable {
  func controlTransfer(_: USBControlTransferRequest, timeout _: UInt32) throws -> [UInt8] {
    throw USBTransportError.notSupported
  }

  func write(endpoint _: UInt8, data: [UInt8], timeout _: UInt32) -> Int { data.count }

  func read(endpoint _: UInt8, length _: Int, timeout _: UInt32) throws -> [UInt8] {
    throw USBTransportError.disconnected
  }
}
