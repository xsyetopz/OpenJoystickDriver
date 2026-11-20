import Foundation
import IOKit
import OpenJoystickDriverKit

/// Counts the IOKit publications and terminations of the services a raw-USB listing reads: every
/// `IOUSBHostDevice`, and the services of OJD's DriverKit extension.
///
/// The count is nil when a notification cannot be registered, so each poll lists the devices.
@safe
final class USBEnumerationWatch: @unchecked Sendable {
  /// The watch that every facade in the process shares.
  static let shared = USBEnumerationWatch()

  /// The notifications seen, or nil when the watch could not start.
  private let changes = Locked<UInt64?>(nil)
  /// The queue that delivers the notifications.
  private let queue = DispatchQueue(label: "com.openjoystickdriver.usb.enumeration")
  /// The notification port, kept for the life of the process.
  private var port: IONotificationPortRef?

  /// Starts the notifications.
  private init() { queue.sync { start() } }

  /// The notifications seen so far, or nil when the watch could not start.
  var changeCount: UInt64? { changes.withLock { $0 } }

  /// Registers a publication and a termination notification for each watched service class.
  ///
  /// Runs on `queue`, so no notification counts before the registrations finish.
  private func start() {
    guard let created = unsafe IONotificationPortCreate(kIOMainPortDefault) else { return }
    unsafe port = created
    unsafe IONotificationPortSetDispatchQueue(created, queue)
    let refcon = unsafe Unmanaged.passUnretained(self).toOpaque()
    for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
      for matching in Self.matchingDictionaries() {
        var iterator: io_iterator_t = 0
        let result = unsafe IOServiceAddMatchingNotification(
          created,
          type,
          matching,
          { refcon, iterator in
            guard let owner = unsafe refcon else { return }
            releaseRemaining(iterator)
            unsafe Unmanaged<USBEnumerationWatch>.fromOpaque(owner).takeUnretainedValue().record()
          },
          refcon,
          &iterator
        )
        guard result == kIOReturnSuccess else { return }
        // A notification arms only once its iterator has been read to the end.
        releaseRemaining(iterator)
      }
    }
    changes.withLock { $0 = 0 }
  }

  /// Counts one notification.
  private func record() { changes.withLock { $0 = $0.map { $0 &+ 1 } } }

  /// A fresh matching dictionary per watched class, since each registration consumes its own.
  private static func matchingDictionaries() -> [CFDictionary] {
    guard let devices = unsafe IOServiceMatching("IOUSBHostDevice"),
      let extensionServices = unsafe IOServiceMatching("IOUserService") as NSMutableDictionary?
    else { return [] }
    extensionServices[kIOPropertyMatchKey] = [
      kCFBundleIdentifierKey as String: USBDriverKitExtensionConfiguration.extensionID
    ]
    return [devices, extensionServices]
  }
}

/// Releases each object left in `iterator`.
private func releaseRemaining(_ iterator: io_iterator_t) {
  while case let object = IOIteratorNext(iterator), object != 0 { IOObjectRelease(object) }
}
