import Foundation
import IOKit.hid

/// Manages discovery of USB class 0x03 (HID) game controllers via IOKit.
///
/// This is the entry point for HID-class devices (for example, DualShock 4).
/// It wraps `HIDDeviceStream` and exposes a single async stream of device
/// events. USB class 0xFF (vendor-specific) devices use SwiftUSB instead.
public final class HIDManager: Sendable {
  private let stream: HIDDeviceStream

  /// Creates a new HIDManager.
  ///
  /// - Parameters:
  ///   - virtualProfile: Profile of the virtual device to exclude from detection.
  ///   - additionalProfileIdentifiers: Exact profile-backed HID devices whose top-level
  ///     usage is not necessarily GamePad.
  public init(
    virtualProfile: VirtualDeviceProfile = .default,
    additionalProfileIdentifiers: [DeviceIdentifier] = []
  ) {
    stream = HIDDeviceStream(
      virtualProfile: virtualProfile,
      additionalProfileIdentifiers: additionalProfileIdentifiers
    )
  }

  /// Returns a live stream of HID device events (connect, disconnect, input report).
  public func deviceEvents() -> AsyncStream<HIDDeviceEvent> { stream.deviceEvents() }

  /// Sends a raw HID output report to the connected device at `locationID`.
  public func setOutputReport(locationID: UInt32, report: PhysicalHIDOutputReport) -> Bool {
    stream.setOutputReport(locationID: locationID, report: report)
  }

  /// Sends a raw HID feature report to the connected device at `locationID`.
  public func setFeatureReport(locationID: UInt32, report: PhysicalHIDOutputReport) -> Bool {
    stream.setFeatureReport(locationID: locationID, report: report)
  }

  /// Reads a raw HID feature report from the connected device at `locationID`.
  public func getFeatureReport(locationID: UInt32, request: PhysicalHIDFeatureReadRequest) -> Data?
  { stream.getFeatureReport(locationID: locationID, request: request) }
}
