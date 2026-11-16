import Foundation
import IOKit
import IOKit.hid
package import OpenJoystickDriverKit

/// The kernel queue between an `IOHIDLibUserClient` and the process that reads its device.
///
/// A client's queue holds `kIOHIDMaxReportBufferCountKey` entries of
/// `kIOHIDReportBufferEntrySizeKey` bytes, 16384 bytes unless a client sets both, and at most
/// 131072 bytes. A report that finds the queue full is dropped and counted as
/// `EnqueueErrorCount` in the client's `DebugState`.
enum HIDInputReportQueue {
  /// The most bytes the kernel gives one client's queue.
  static let maximumBytes = 131_072
  /// The most bytes of one queue entry the kernel accepts.
  static let maximumEntryBytes = 8_167
  /// Reports the queue holds before the reader must catch up.
  static let targetReportCount = 1_024
  /// Bytes an entry carries beside the report itself.
  static let entryOverheadBytes = 32

  /// The size of one queue entry and the number of reports the queue holds.
  struct Sizing: Equatable {
    /// The bytes of one entry.
    let entrySize: Int
    /// The reports the queue holds.
    let reportCount: Int
  }

  /// The entry size and report count for a device whose reports are at most
  /// `maxInputReportSize` bytes: ``targetReportCount`` reports, fewer when the entry size would
  /// take the queue over ``maximumBytes``; nil when one entry cannot fit the limits.
  static func sizing(maxInputReportSize: Int) -> Sizing? {
    let entrySize = max(maxInputReportSize, 1) + entryOverheadBytes
    guard entrySize <= maximumEntryBytes else { return nil }
    return Sizing(
      entrySize: entrySize,
      reportCount: min(targetReportCount, maximumBytes / entrySize)
    )
  }

  /// Sets the queue size on the open client connection of `device`.
  ///
  /// The kernel takes the properties only on an open connection: set before `IOHIDDeviceOpen` they
  /// are refused. Returns false when the device refused either property, which leaves the default
  /// queue.
  static func size(_ device: IOHIDDevice, maxInputReportSize: Int) -> Bool {
    guard let sizing = sizing(maxInputReportSize: maxInputReportSize) else { return false }
    let entry = IOHIDDeviceSetProperty(
      device,
      kIOHIDReportBufferEntrySizeKey as CFString,
      sizing.entrySize as CFNumber
    )
    let count = IOHIDDeviceSetProperty(
      device,
      kIOHIDMaxReportBufferCountKey as CFString,
      sizing.reportCount as CFNumber
    )
    return entry && count
  }
}

/// Reads the dropped input report count of a process from the IORegistry.
package enum HIDInputReportDrops {
  /// The sum of `EnqueueErrorCount` over the event queues in a client's `DebugState`; nil when
  /// the properties carry no queue map.
  static func droppedReports(inClientProperties properties: [String: Any]) -> Int? {
    guard let debugState = properties["DebugState"] as? [String: Any],
      let queues = debugState["EventQueueMap"] as? [[String: Any]]
    else { return nil }
    return queues.reduce(0) { $0 + ($1["EnqueueErrorCount"] as? Int ?? 0) }
  }

  /// Whether the `IOUserClientCreator` property (`pid 123, name`) names process `processID`.
  static func creator(_ creator: String, isProcess processID: Int32) -> Bool {
    creator.hasPrefix("pid \(processID),")
  }

  /// The drop counts of the HID clients that process `processID` holds on devices, one per
  /// client that reports a queue.
  package static func observations(processID: Int32) -> [HIDInputDropObservation] {
    var iterator = io_iterator_t()
    guard
      unsafe IORegistryCreateIterator(
        kIOMainPortDefault,
        kIOServicePlane,
        IOOptionBits(kIORegistryIterateRecursively),
        &iterator
      ) == KERN_SUCCESS
    else { return [] }
    defer { IOObjectRelease(iterator) }
    var result: [HIDInputDropObservation] = []
    while case let entry = IOIteratorNext(iterator), entry != 0 {
      defer { IOObjectRelease(entry) }
      guard unsafe IOObjectConformsTo(entry, "IOHIDLibUserClient") != 0,
        let properties = registryProperties(entry),
        let creator = properties["IOUserClientCreator"] as? String,
        Self.creator(creator, isProcess: processID),
        let dropped = droppedReports(inClientProperties: properties)
      else { continue }
      var parent = io_registry_entry_t()
      guard unsafe IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS
      else {
        continue
      }
      defer { IOObjectRelease(parent) }
      guard let device = registryProperties(parent) else { continue }
      result.append(
        HIDInputDropObservation(
          productName: device[kIOHIDProductKey] as? String ?? "",
          vendorID: device[kIOHIDVendorIDKey] as? Int ?? 0,
          productID: device[kIOHIDProductIDKey] as? Int ?? 0,
          droppedReports: dropped
        )
      )
    }
    return result
  }

  /// Copies the registry properties of `entry`, or returns nil when they cannot be read.
  static func registryProperties(_ entry: io_registry_entry_t) -> [String: Any]? {
    var properties: Unmanaged<CFMutableDictionary>?
    guard
      unsafe IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0)
        == KERN_SUCCESS
    else { return nil }
    return unsafe properties?.takeRetainedValue() as? [String: Any]
  }
}
