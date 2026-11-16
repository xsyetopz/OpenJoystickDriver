import Foundation
import IOKit
import IOKit.pwr_mgt

/// A message from the root power domain.
enum SystemPowerMessage: Equatable, Sendable {
  /// The system considers an idle sleep and asks every client to allow or veto it.
  case canSystemSleep(notificationID: Int)
  /// The system sleeps and waits for every client to acknowledge.
  case systemWillSleep(notificationID: Int)
  /// The system woke and the hardware is powered.
  case systemHasPoweredOn
}

/// A source of root power domain messages and the call that acknowledges them.
protocol SystemPowerSource: Sendable {
  /// Starts delivering messages to `onMessage`, which may run on any thread.
  func start(onMessage: @escaping @Sendable (SystemPowerMessage) -> Void)
  /// Acknowledges `notificationID` so the system may continue its power change.
  func allowPowerChange(notificationID: Int)
  /// Stops delivering messages. Acknowledgements after this call do nothing.
  func stop()
}

/// The root power domain through `IORegisterForSystemPower`.
///
/// - Note: `@unchecked Sendable` because `lock` guards every mutable property.
@safe
final class IOKitSystemPowerSource: SystemPowerSource, @unchecked Sendable {
  /// `kIOMessageCanSystemSleep`, which Swift does not import from its function-like macro.
  private static let canSystemSleep: UInt32 = 0xE000_0270
  /// `kIOMessageSystemWillSleep`.
  private static let systemWillSleep: UInt32 = 0xE000_0280
  /// `kIOMessageSystemHasPoweredOn`.
  private static let systemHasPoweredOn: UInt32 = 0xE000_0300

  /// Guards the mutable state below.
  private let lock = NSLock()
  /// The queue that receives the IOKit callbacks.
  private let queue = DispatchQueue(label: "OpenJoystickDriver.SystemPower")
  /// The receiver of messages.
  private var onMessage: (@Sendable (SystemPowerMessage) -> Void)?
  /// The connection to the root power domain, or zero.
  private var rootPort: io_connect_t = 0
  /// The notification port.
  private var notificationPort: IONotificationPortRef?
  /// The notifier to deregister.
  private var notifier: io_object_t = 0

  /// Creates a source that registers on ``start(onMessage:)``.
  init() {}

  /// Registers for system power and sets the callback queue.
  func start(onMessage: @escaping @Sendable (SystemPowerMessage) -> Void) {
    lock.lock()
    defer { lock.unlock() }
    guard rootPort == 0 else { return }
    self.onMessage = onMessage
    var port: IONotificationPortRef?
    var registered: io_object_t = 0
    let refcon = unsafe Unmanaged.passUnretained(self).toOpaque()
    let root = unsafe IORegisterForSystemPower(
      refcon,
      &port,
      { rawRefcon, _, messageType, argument in
        guard let instance = unsafe rawRefcon else { return }
        unsafe Unmanaged<IOKitSystemPowerSource>.fromOpaque(instance).takeUnretainedValue()
          .receive(messageType: messageType, argument: argument)
      },
      &registered
    )
    guard root != 0, let created = unsafe port else { return }
    unsafe IONotificationPortSetDispatchQueue(created, queue)
    rootPort = root
    unsafe notificationPort = unsafe created
    self.notifier = registered
  }

  /// Calls `IOAllowPowerChange`.
  func allowPowerChange(notificationID: Int) {
    lock.lock()
    let root = rootPort
    lock.unlock()
    guard root != 0 else { return }
    IOAllowPowerChange(root, notificationID)
  }

  /// Deregisters and closes the connection.
  func stop() {
    lock.lock()
    let root = rootPort
    let port = unsafe notificationPort
    var token = self.notifier
    rootPort = 0
    unsafe notificationPort = nil
    self.notifier = 0
    onMessage = nil
    lock.unlock()
    guard root != 0 else { return }
    unsafe IODeregisterForSystemPower(&token)
    IOServiceClose(root)
    if let live = unsafe port { unsafe IONotificationPortDestroy(live) }
  }

  /// Passes a callback to the receiver.
  private func receive(messageType: UInt32, argument: UnsafeMutableRawPointer?) {
    let notificationID = Int(bitPattern: argument)
    let message: SystemPowerMessage
    switch messageType {
    case Self.canSystemSleep: message = .canSystemSleep(notificationID: notificationID)
    case Self.systemWillSleep: message = .systemWillSleep(notificationID: notificationID)
    case Self.systemHasPoweredOn: message = .systemHasPoweredOn
    default: return
    }
    lock.lock()
    let callback = onMessage
    lock.unlock()
    callback?(message)
  }
}
