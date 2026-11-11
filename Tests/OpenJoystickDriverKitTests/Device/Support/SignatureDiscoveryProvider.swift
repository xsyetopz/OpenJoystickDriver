import Foundation

@testable import OpenJoystickDriverKit

/// Passive facts before configuration, and the facts a configuration read returns.
actor SignatureDiscoveryProvider: USBTransportProvider {
  let device: USBTransportDevice
  let passive: PhysicalDevice
  let configured: PhysicalDevice?
  let configurationError: USBTransportError?
  let session = USBManagerResolutionSession()
  private(set) var descriptorReads: [UInt8] = []
  private(set) var options: USBTransportOpenOptions?
  private(set) var openCount = 0

  init(
    device: USBTransportDevice,
    passive: PhysicalDevice,
    configured: PhysicalDevice?,
    configurationError: USBTransportError? = nil
  ) {
    self.device = device
    self.passive = passive
    self.configured = configured
    self.configurationError = configurationError
  }

  func devices() -> [USBTransportDevice] { [device] }

  func physicalDeviceObservation(for _: USBTransportDevice) -> PhysicalDevice? { passive }

  func resolveTransport(
    for _: USBTransportDevice,
    configured profile: DeviceTransportProfile
  ) -> USBTransportResolution { USBTransportResolution(profile: profile, physicalDevice: passive) }

  func configurationObservation(
    for _: USBTransportDevice,
    configurationValue: UInt8
  ) throws -> PhysicalDevice? {
    descriptorReads.append(configurationValue)
    if let configurationError { throw configurationError }
    return configured
  }

  func open(
    _: USBTransportDevice,
    options: USBTransportOpenOptions
  ) -> any USBTransportSession {
    self.options = options
    openCount += 1
    return session
  }
}
