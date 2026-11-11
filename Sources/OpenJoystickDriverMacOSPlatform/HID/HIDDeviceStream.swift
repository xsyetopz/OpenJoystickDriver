import Foundation
import IOKit
import IOKit.hid
package import OpenJoystickDriverKit

/// Watches for HID-class game controllers using Apple's IOKit HID framework.
///
/// Creates an `AsyncStream` of device connect, disconnect, and input report
/// events. IOKit delivers callbacks on the main run loop, and this class
/// forwards them into the stream for safe async consumption.
@safe
package final class HIDDeviceStream: @unchecked Sendable {

  // MARK: - Thread safety
  //
  // @unchecked Sendable safety:
  // - All IOKit callbacks are scheduled on the main run loop
  // - `deviceEvents()` and `cleanup()` run on main, so `continuation`, `streamGeneration`, device
  //   admission, and report-buffer lifetime are confined to the main thread
  // - `seizeLock` guards the device maps, which output paths also read off main
  // - `deviceEvents()` terminates any existing stream before creating a new one

  /// The manager of the current stream, created by each `deviceEvents()` and released by
  /// `cleanup()`.
  ///
  /// A manager unscheduled across system sleep does not learn of devices that enumerated meanwhile,
  /// so a restarted stream never reuses one. Main-confined.
  var manager: IOHIDManager?
  /// The continuation of the current event stream, set by each `deviceEvents()`.
  var continuation: AsyncStream<HIDDeviceEvent>.Continuation?
  /// The number of the current stream; a callback of an earlier stream is ignored.
  var streamGeneration = 0
  /// The lock that guards the device maps.
  let seizeLock = NSLock()
  /// Mode probe reads, which give up at a deadline and are not repeated on a silent device.
  let boundedReads = BoundedHIDRead()
  /// The devices that this stream seized, by location ID.
  var seizedByLocation: [UInt32: [IOHIDDevice]] = [:]
  /// The devices whose input claim is released, by location ID.
  var releasedByLocation: [UInt32: [IOHIDDevice]] = [:]
  /// The connections of the tracked devices, by device ID.
  var connectionsByDeviceID: [UInt64: HIDDeviceConnection] = [:]
  /// Admitted devices this stream opened for shared input, with their input report buffers.
  var sharedOpenByDeviceID: [UInt64: SharedOpenDevice] = unsafe [:]
  /// The adapter that turns device events into backend events.
  let eventAdapter = SynchronizedPhysicalHIDBackendEventAdapter()
  /// Models whose family declares HID protocol roles; each of their devices disconnects on its own
  /// removal instead of when its location empties.
  ///
  /// Set by each `deviceEvents()`.
  var roleModels: Set<ControllerModelID> = []
  /// Returns the models that the controller records add to the matching.
  private let additionalProfileModels: @Sendable () -> [ControllerModelID]
  /// Returns the models whose family declares HID protocol roles.
  private let roleProfileModels: @Sendable () -> [ControllerModelID]

  /// Creates a stream that matches HID gamepad devices.
  ///
  /// The model providers are read by each `deviceEvents()`, so a stream started again after
  /// the controller records change matches the changed records.
  @preconcurrency
  package init(
    additionalProfileModels: @escaping @Sendable () -> [ControllerModelID] = { [] },
    roleProfileModels: @escaping @Sendable () -> [ControllerModelID] = { [] }
  ) {
    self.additionalProfileModels = additionalProfileModels
    self.roleProfileModels = roleProfileModels
  }

  /// Reads the current models into ``roleModels`` and returns the matching to apply.
  ///
  /// Applied by each `deviceEvents()`, not at init: setting matching makes IOKit create a device
  /// object, and load its plug-in, for every attached match.
  func currentDeviceMatching() -> CFArray {
    roleModels = Set(roleProfileModels())
    var matches: [[String: Any]] = [
      [
        kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
        kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad,
      ]
    ]
    matches += additionalProfileModels().map {
      [
        kIOHIDVendorIDKey: Int($0.vendorID),
        kIOHIDProductIDKey: Int($0.productID),
      ]
    }
    return matches.map { AppleGameControllerSyntheticHID.ioHIDMatchingExcludingSynthetics($0) }
      as CFArray
  }

  /// A device that this stream opened for shared input, with its input report buffer.
  @unsafe
  struct SharedOpenDevice {
    /// The opened device.
    let device: IOHIDDevice
    /// The buffer that receives the input reports of the device.
    let reportBuffer: UnsafeMutableBufferPointer<UInt8>
  }

  // MARK: - C-convention callbacks

  /// The callback for a device that matches.
  static let matchingCallback: IOHIDDeviceCallback = { rawContext, _, _, device in
    guard let context = unsafe rawContext else { return }
    unsafe Unmanaged<HIDDeviceStream>.fromOpaque(context).takeUnretainedValue().handleDeviceAdded(
      device
    )
  }

  /// The callback for a device that is removed.
  static let removalCallback: IOHIDDeviceCallback = { rawContext, _, _, device in
    guard let context = unsafe rawContext else { return }
    unsafe Unmanaged<HIDDeviceStream>.fromOpaque(context).takeUnretainedValue().handleDeviceRemoved(
      device
    )
  }

  /// The callback for an input element value.
  static let inputValueCallback: IOHIDValueCallback = { rawContext, _, _, value in
    guard let context = unsafe rawContext else { return }
    unsafe Unmanaged<HIDDeviceStream>.fromOpaque(context).takeUnretainedValue().handleInputValue(
      value
    )
  }

  /// The callback for an input report.
  static let inputReportCallback: IOHIDReportCallback = {
    rawContext,
    _,
    rawSender,
    _,
    reportID,
    report,
    length in
    guard let context = unsafe rawContext, let sender = unsafe rawSender else { return }
    let device = unsafe Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
    let stream = unsafe Unmanaged<HIDDeviceStream>.fromOpaque(context).takeUnretainedValue()
    unsafe stream.handleInputReport(
      deviceID: stream.trackingID(for: device),
      reportID: UInt8(truncatingIfNeeded: reportID),
      report: report,
      reportLength: length
    )
  }
}
