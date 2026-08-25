import Foundation

protocol HIDAccessBackend: Sendable {
  func deviceEvents() async -> AsyncStream<HIDDeviceEvent>
  func setOutputReport(locationID: UInt32, report: PhysicalHIDOutputReport) async -> Bool
  func setFeatureReport(locationID: UInt32, report: PhysicalHIDOutputReport) async -> Bool
  func getFeatureReport(locationID: UInt32, request: PhysicalHIDFeatureReadRequest) async -> Data?
}

@available(macOS, introduced: 10.15, obsoleted: 15.0)
private final class IOHIDAccessBackend: HIDAccessBackend, Sendable {
  private let stream: HIDDeviceStream

  init(virtualProfile: VirtualDeviceProfile, additionalProfileIdentifiers: [DeviceIdentifier]) {
    stream = HIDDeviceStream(
      virtualProfile: virtualProfile,
      additionalProfileIdentifiers: additionalProfileIdentifiers
    )
  }

  func deviceEvents() async -> AsyncStream<HIDDeviceEvent> {
    await Task.yield()
    return stream.deviceEvents()
  }

  func setOutputReport(locationID: UInt32, report: PhysicalHIDOutputReport) -> Bool {
    stream.setOutputReport(locationID: locationID, report: report)
  }

  func setFeatureReport(locationID: UInt32, report: PhysicalHIDOutputReport) -> Bool {
    stream.setFeatureReport(locationID: locationID, report: report)
  }

  func getFeatureReport(locationID: UInt32, request: PhysicalHIDFeatureReadRequest) -> Data? {
    stream.getFeatureReport(locationID: locationID, request: request)
  }
}

/// Availability-selecting app HID access wrapper.
///
/// IOHIDManager owns macOS 10.15–14. CoreHID owns macOS 15 and later. Callers
/// depend only on this wrapper and never repeat availability checks.
public final class HIDManager: Sendable {
  private let backend: any HIDAccessBackend

  public init(
    virtualProfile: VirtualDeviceProfile = .default,
    additionalProfileIdentifiers: [DeviceIdentifier] = []
  ) {
    if #available(macOS 15, *) {
      backend = CoreHIDAccessBackend(
        virtualProfile: virtualProfile,
        additionalProfileIdentifiers: additionalProfileIdentifiers
      )
    } else {
      backend = IOHIDAccessBackend(
        virtualProfile: virtualProfile,
        additionalProfileIdentifiers: additionalProfileIdentifiers
      )
    }
  }

  public func deviceEvents() async -> AsyncStream<HIDDeviceEvent> { await backend.deviceEvents() }

  public func setOutputReport(locationID: UInt32, report: PhysicalHIDOutputReport) async -> Bool {
    await backend.setOutputReport(locationID: locationID, report: report)
  }

  public func setFeatureReport(locationID: UInt32, report: PhysicalHIDOutputReport) async -> Bool {
    await backend.setFeatureReport(locationID: locationID, report: report)
  }

  public func getFeatureReport(locationID: UInt32, request: PhysicalHIDFeatureReadRequest) async
    -> Data?
  { await backend.getFeatureReport(locationID: locationID, request: request) }
}
