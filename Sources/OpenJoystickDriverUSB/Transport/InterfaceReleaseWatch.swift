import Foundation
import IOKit
import OpenJoystickDriverKit

/// Waits for one IOKit interest notification that ends an exclusive hold on an interface.
///
/// `kIOMessageServiceWasClosed` is sent when a client closes the service and
/// `kIOMessageServiceIsTerminated` when the service goes away (`IOMessage.h`; both are
/// function-like macros that Swift does not import). Any other message ends the wait only once the
/// interface names no owner.
@safe
final class InterfaceReleaseWatch: @unchecked Sendable {
  /// The IOKit message type that says a client closed the service.
  private static let wasClosed: UInt32 = 0xE000_0110
  /// The IOKit message type that says the service terminated.
  private static let isTerminated: UInt32 = 0xE000_0010

  /// The lock that guards `continuation` and `finished`.
  private let lock = NSLock()
  /// The waiting task, until the watch finishes.
  private var continuation: CheckedContinuation<Void, Never>?
  /// Whether the watch finished.
  private var finished = false
  /// The notification port.
  private var port: IONotificationPortRef?
  /// The interest notification object.
  private var notification: io_object_t = 0
  /// The queue that delivers the notifications.
  private let queue = DispatchQueue(label: "com.openjoystickdriver.iousbhost.release")
  /// The watched interface service, retained until ``stop()``.
  private var service: io_service_t = 0

  /// Registers the interest notification on `service`.
  ///
  /// Finishes at once when the interface already names no owner.
  ///
  /// - Throws: ``USBTransportError/platform(code:message:)`` when the port cannot be created, and
  ///   the mapped IOKit error when the registration fails.
  func start(service: io_service_t) throws {
    guard let created = unsafe IONotificationPortCreate(kIOMainPortDefault) else {
      throw USBTransportError.platform(code: 0, message: "IONotificationPortCreate failed")
    }
    unsafe self.port = created
    unsafe IONotificationPortSetDispatchQueue(created, queue)
    IOObjectRetain(service)
    self.service = service
    let result = unsafe IOServiceAddInterestNotification(
      created,
      service,
      kIOGeneralInterest,
      { refcon, _, messageType, _ in
        guard let owner = unsafe refcon else { return }
        unsafe Unmanaged<InterfaceReleaseWatch>.fromOpaque(owner).takeUnretainedValue()
          .received(messageType)
      },
      unsafe Unmanaged.passUnretained(self).toOpaque(),
      &notification
    )
    guard result == kIOReturnSuccess else {
      stop()
      throw IOUSBHostTransportProvider.transportError(result)
    }
    // The owner may have let go between the failed open and the registration.
    if !hasOwnerKey(service) { finish() }
  }

  /// Suspends until the watch finishes.
  func wait() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      lock.lock()
      if finished {
        lock.unlock()
        continuation.resume()
      } else {
        self.continuation = continuation
        lock.unlock()
      }
    }
  }

  /// Ends the watch and resumes the waiting task.
  func finish() {
    lock.lock()
    finished = true
    let waiting = self.continuation
    self.continuation = nil
    lock.unlock()
    waiting?.resume()
  }

  /// Runs on the notification queue, so no callback reads `service` while it is released.
  func stop() {
    queue.sync(execute: release)
  }

  /// Releases the notification, the port and the service.
  private func release() {
    if notification != 0 {
      IOObjectRelease(notification)
      notification = 0
    }
    if let open = unsafe port {
      unsafe IONotificationPortDestroy(open)
      unsafe self.port = nil
    }
    if service != 0 {
      IOObjectRelease(service)
      service = 0
    }
  }

  /// Finishes the watch for a close or terminate message, or when the interface names no owner.
  private func received(_ messageType: UInt32) {
    if messageType == Self.wasClosed || messageType == Self.isTerminated || !hasOwnerKey(service) {
      finish()
    }
  }

  /// Tells whether `service` still names an exclusive owner.
  private func hasOwnerKey(_ service: io_service_t) -> Bool {
    unsafe IORegistryEntryCreateCFProperty(
      service,
      IOUSBHostTransportProvider.exclusiveOwnerKey as CFString,
      kCFAllocatorDefault,
      0
    ) != nil
  }
}
