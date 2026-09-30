import Foundation
import IOKit
import IOKit.hid

/// Watches for HID-class game controllers using Apple's IOKit HID framework.
///
/// Creates an `AsyncStream` of device connect, disconnect, and input report
/// events. IOKit delivers callbacks on the main run loop, and this class
/// forwards them into the stream for safe async consumption.
public final class HIDDeviceStream: @unchecked Sendable {

  // MARK: - Thread safety
  //
  // @unchecked Sendable safety:
  // - All IOKit callbacks are scheduled on the main run loop
  // - `deviceEvents()` and `cleanup()` run on main, so `continuation`, `streamGeneration`, device
  //   admission, and report-buffer lifetime are confined to the main thread
  // - `seizeLock` guards the device maps, which output paths also read off main
  // - `deviceEvents()` terminates any existing stream before creating a new one

  /// The manager of the current stream, created by each `deviceEvents()` and released by
  /// `cleanup()`. A manager unscheduled across system sleep does not learn of devices that
  /// enumerated meanwhile, so a restarted stream never reuses one. Main-confined.
  var manager: IOHIDManager?
  var continuation: AsyncStream<HIDDeviceEvent>.Continuation?
  var streamGeneration = 0
  let seizeLock = NSLock()
  var seizedByLocation: [UInt32: [IOHIDDevice]] = [:]
  var releasedByLocation: [UInt32: [IOHIDDevice]] = [:]
  var connectionsByDeviceID: [UInt64: HIDDeviceConnection] = [:]
  /// Admitted devices this stream opened for shared input, with their input report buffers.
  var sharedOpenByDeviceID: [UInt64: SharedOpenDevice] = [:]
  let eventAdapter = SynchronizedPhysicalHIDBackendEventAdapter()
  /// Models whose family declares HID protocol roles; each of their devices disconnects on its
  /// own removal instead of when its location empties. Set by each `deviceEvents()`.
  var roleModels: Set<PhysicalHIDIdentity> = []
  private let additionalProfileIdentifiers: @Sendable () -> [DeviceIdentifier]
  private let roleProfileIdentifiers: @Sendable () -> [DeviceIdentifier]

  /// Creates a new stream that matches HID gamepad devices.
  ///
  /// The identifier providers are read by each `deviceEvents()`, so a stream started again after
  /// the controller records change matches the new records.
  @preconcurrency
  public init(
    additionalProfileIdentifiers: @escaping @Sendable () -> [DeviceIdentifier] = { [] },
    roleProfileIdentifiers: @escaping @Sendable () -> [DeviceIdentifier] = { [] }
  ) {
    self.additionalProfileIdentifiers = additionalProfileIdentifiers
    self.roleProfileIdentifiers = roleProfileIdentifiers
  }

  /// Reads the current models into ``roleModels`` and returns the matching to apply. Applied by
  /// each `deviceEvents()`, not at init: setting matching makes IOKit create a device object, and
  /// load its plug-in, for every attached match.
  func currentDeviceMatching() -> CFArray {
    roleModels = Set(
      roleProfileIdentifiers().compactMap {
        PhysicalHIDIdentity(
          vendorID: UInt64($0.controllerIdentity.vendorID),
          productID: UInt64($0.controllerIdentity.productID)
        )
      }
    )
    var matches: [[String: Any]] = [
      [
        kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
        kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad,
      ]
    ]
    matches += additionalProfileIdentifiers().map {
      [
        kIOHIDVendorIDKey: Int($0.controllerIdentity.vendorID),
        kIOHIDProductIDKey: Int($0.controllerIdentity.productID),
      ]
    }
    return matches.map { AppleGameControllerSyntheticHID.ioHIDMatchingExcludingSynthetics($0) }
      as CFArray
  }

  struct SharedOpenDevice {
    let device: IOHIDDevice
    let reportBuffer: UnsafeMutableBufferPointer<UInt8>
  }

  // MARK: - C-convention callbacks

  static let matchingCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<HIDDeviceStream>.fromOpaque(context).takeUnretainedValue().handleDeviceAdded(device)
  }

  static let removalCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<HIDDeviceStream>.fromOpaque(context).takeUnretainedValue().handleDeviceRemoved(device)
  }

  static let inputValueCallback: IOHIDValueCallback = { context, _, _, value in
    guard let context else { return }
    Unmanaged<HIDDeviceStream>.fromOpaque(context).takeUnretainedValue().handleInputValue(value)
  }

  static let inputReportCallback: IOHIDReportCallback = {
    context,
    _,
    sender,
    _,
    reportID,
    report,
    length in
    guard let context, let sender else { return }
    let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
    let loc = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int ?? 0
    let stream = Unmanaged<HIDDeviceStream>.fromOpaque(context).takeUnretainedValue()
    stream.handleInputReport(
      deviceID: stream.trackingID(for: device),
      locationID: UInt32(truncatingIfNeeded: loc),
      reportID: UInt8(truncatingIfNeeded: reportID),
      report: report,
      reportLength: length
    )
  }
}
