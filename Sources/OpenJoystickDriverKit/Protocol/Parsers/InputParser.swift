import Foundation
import SwiftUSB

/// Turns raw bytes from a controller into ``ControllerEvent`` values.
///
/// Each controller protocol (GIP for Xbox, DS4 for PlayStation, GenericHID)
/// has its own implementation. Add a new conforming type when you need to
/// support a new protocol.

/// Receiver-backed controllers can report logical controller connect/disconnect
/// independently from the HID device that carries reports.
public enum ControllerInputConnectionState: Sendable, Equatable {
  case connected
  case disconnected
}

/// Optional parser hook for logical controller lifecycle inside a physical input transport.
public protocol ControllerInputConnectionLifecycle: AnyObject, Sendable {
  /// True when output should not be created until a logical controller connect event arrives.
  var requiresInputConnectionBeforeOutput: Bool { get }

  /// Returns and clears the most recent logical connection state change, if any.
  func consumeInputConnectionStateChange() -> ControllerInputConnectionState?
}

/// Optional parser hook for receiver status requests over HID feature reports.
public protocol HIDInputConnectionStatusRequester: AnyObject, Sendable {
  /// Feature report that asks the receiver to emit its current logical connection state.
  func inputConnectionStatusRequestReport() -> PhysicalHIDOutputReport?
}

/// Optional parser hook for startup output reports sent through a HID transport.
public protocol HIDStartupOutputReportProvider: AnyObject, Sendable {
  /// Source-backed startup reports needed before the controller emits full input reports.
  func hidStartupReports() -> [PhysicalHIDOutputReport]

  /// Minimum interval between startup reports for the selected transport.
  func hidStartupReportIntervalNanoseconds(transport: String?) -> UInt64
}

extension HIDStartupOutputReportProvider {
  /// Source-backed startup reports for a specific HID transport, when transport matters.
  public func hidStartupReports(transport _: String?) -> [PhysicalHIDOutputReport] {
    hidStartupReports()
  }

  public func hidStartupReportIntervalNanoseconds(transport _: String?) -> UInt64 { 0 }
}

/// Optional USB output emitted when a receiver-backed controller connects or disconnects.
public protocol USBInputConnectionOutputProvider: AnyObject, Sendable {
  /// Source-backed packets for one logical controller lifecycle transition.
  func usbInputConnectionOutputPackets(
    for state: ControllerInputConnectionState
  ) -> [[UInt8]]
}

/// Optional parser hook for startup output packets sent through a USB interrupt OUT endpoint.
public protocol USBStartupOutputProvider: AnyObject, Sendable {
  /// Source-backed startup packets needed when OJD starts consuming a USB controller.
  func usbStartupOutputPackets() -> [[UInt8]]
}

/// Optional parser hook for startup feature reports sent through a HID transport.
public protocol HIDStartupFeatureReportProvider: AnyObject, Sendable {
  /// Source-backed feature reports needed when OJD starts consuming the physical input.
  func hidStartupFeatureReports() -> [PhysicalHIDOutputReport]
}

extension HIDStartupFeatureReportProvider {
  /// Source-backed feature reports for a specific HID transport, when transport matters.
  public func hidStartupFeatureReports(transport _: String?) -> [PhysicalHIDOutputReport] {
    hidStartupFeatureReports()
  }
}

/// Optional parser hook for shutdown feature reports sent through a HID transport.
public protocol HIDShutdownFeatureReportProvider: AnyObject, Sendable {
  /// Source-backed feature reports needed when OJD stops consuming the physical input.
  func hidShutdownFeatureReports() -> [PhysicalHIDOutputReport]
}

/// Optional parser hook for startup feature-report reads sent through a HID transport.
public protocol HIDStartupFeatureReadRequestProvider: AnyObject, Sendable {
  /// Source-backed feature reads needed to put the controller into operational mode.
  func hidStartupFeatureReadRequests() -> [PhysicalHIDFeatureReadRequest]
}

extension HIDStartupFeatureReadRequestProvider {
  /// Source-backed feature reads for a specific HID transport, when transport matters.
  public func hidStartupFeatureReadRequests(transport _: String?)
    -> [PhysicalHIDFeatureReadRequest]
  {
    hidStartupFeatureReadRequests()
  }
}

/// Optional semantic input path for descriptor-defined HID gamepads.
public protocol HIDElementValueParser: AnyObject, Sendable {
  /// Converts one IOKit-decoded HID element value into controller events.
  func parse(elementValue: HIDElementValue) -> [ControllerEvent]
}

public protocol InputParser: AnyObject, Sendable {
  /// Runs the startup handshake the controller needs before it starts sending input.
  ///
  /// For example, GIP controllers require a power-on packet. Protocols that
  /// have no handshake (DS4, GenericHID) leave this as a no-op.
  /// - Parameter handle: The USB device handle. Pass `nil` for HID devices.
  /// - Throws: A protocol-specific error if the handshake fails.
  func performHandshake(handle: USBDeviceHandle?) async throws

  /// Reads one raw data packet and returns zero or more controller events.
  ///
  /// Called once for every USB interrupt transfer or HID input report the
  /// system receives from the controller.
  func parse(data: Data) throws -> [ControllerEvent]

  /// Sends a keep-alive packet so the controller does not power off.
  ///
  /// ``DevicePipeline`` calls this at a regular interval during the input
  /// loop. The default implementation does nothing; override it if the
  /// protocol requires periodic pings (GIP uses CMD 0x03).
  func keepAlive(handle: USBDeviceHandle?) throws
}

extension InputParser {
  /// Default no-op keep-alive implementation.
  public func keepAlive(handle: USBDeviceHandle?) throws {}
}
