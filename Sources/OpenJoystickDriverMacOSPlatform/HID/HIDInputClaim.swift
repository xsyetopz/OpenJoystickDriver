import IOKit
import IOKit.hid
import OpenJoystickDriverKit

/// The two device calls that open and close one IOHID device object.
///
/// A fake records the calls in tests.
struct HIDDeviceOpenPort {
  /// Opens the device object with the given options.
  let open: (IOOptionBits) -> IOReturn
  /// Closes the device object with the given options.
  let close: (IOOptionBits) -> IOReturn

  /// Creates a port from an open call and a close call.
  init(
    open: @escaping (IOOptionBits) -> IOReturn,
    close: @escaping (IOOptionBits) -> IOReturn
  ) {
    self.open = open
    self.close = close
  }

  /// Creates a port that opens and closes `device`.
  init(device: IOHIDDevice) {
    self.init(
      open: { IOHIDDeviceOpen(device, $0) },
      close: { IOHIDDeviceClose(device, $0) }
    )
  }
}

/// How one device object ended up open after a claim: whether the seize holds, the ownership that
/// names the outcome, and the result of the open that carries input.
///
/// An IOHID device object has one open. IOHIDFamily's `IOHIDDevice::handleOpen` ignores a second
/// open from the same client and returns success without applying its options, so a seize requested
/// after a shared open is never granted while the call reports success. A seize therefore is the
/// first and only open of the object, and a shared open follows it only after the seize was
/// closed.
struct HIDInputClaim: Equatable {
  /// The result of the seize open; nil when no seize was requested.
  let seizeResult: IOReturn?
  /// Whether the device object holds the seize.
  var seized: Bool { seizeResult == kIOReturnSuccess }
  /// The ownership the seize result names; nil when no seize was requested.
  var ownership: HIDInputOwnership? { seizeResult.map(Self.ownership(forSeizeResult:)) }
  /// The result of the open that carries input: the seize when it was granted, else the shared open
  /// that follows it.
  ///
  /// Success means input reports can be read.
  let inputResult: IOReturn

  /// Opens the device object, with the seize when `seize` is set.
  ///
  /// A refused seize is closed first; the object then opens shared, so the refusal is named by
  /// `ownership` and input flows where macOS allows it.
  static func admit(port: HIDDeviceOpenPort, seize: Bool) -> Self {
    guard seize else {
      return Self(seizeResult: nil, inputResult: port.open(IOOptionBits(kIOHIDOptionsTypeNone)))
    }
    return seizeAfterClosing(port: port, closing: nil)
  }

  /// Replaces the shared open with a seize.
  ///
  /// A refused seize is closed and the shared open is restored.
  static func reclaim(port: HIDDeviceOpenPort) -> Self {
    seizeAfterClosing(port: port, closing: IOOptionBits(kIOHIDOptionsTypeNone))
  }

  /// Replaces the seize with a shared open and returns the first failing result.
  static func release(port: HIDDeviceOpenPort) -> IOReturn {
    let closed = port.close(IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
    guard closed == kIOReturnSuccess else { return closed }
    return port.open(IOOptionBits(kIOHIDOptionsTypeNone))
  }

  /// The ownership a seize result names.
  static func ownership(forSeizeResult result: IOReturn) -> HIDInputOwnership {
    switch result {
    case kIOReturnSuccess: .exclusive
    case kIOReturnExclusiveAccess: .ownedByAnotherClient
    case kIOReturnNotPermitted, kIOReturnNotPrivileged: .accessDenied
    default: .acquisitionFailed
    }
  }

  /// Closes a shared open when `sharedOptions` is set, then seizes the device.
  ///
  /// A refused seize is closed, and the device is opened for input without it.
  private static func seizeAfterClosing(
    port: HIDDeviceOpenPort,
    closing sharedOptions: IOOptionBits?
  ) -> Self {
    if let sharedOptions { _ = port.close(sharedOptions) }
    let seizeResult = port.open(IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
    guard seizeResult == kIOReturnSuccess else {
      // A refused seize can leave the client registered with the device; closing it ends that.
      _ = port.close(IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
      return Self(
        seizeResult: seizeResult,
        inputResult: port.open(IOOptionBits(kIOHIDOptionsTypeNone))
      )
    }
    return Self(seizeResult: seizeResult, inputResult: seizeResult)
  }
}
