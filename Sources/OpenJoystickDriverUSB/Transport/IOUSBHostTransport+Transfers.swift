import Foundation
import IOKit
import IOUSBHost
import OpenJoystickDriverKit

extension IOUSBHostTransportProvider {
  /// Converts `request` to the IOUSBHost device request.
  static func deviceRequest(for request: USBControlTransferRequest) -> IOUSBDeviceRequest {
    IOUSBDeviceRequest(
      bmRequestType: request.requestType,
      bRequest: request.request,
      wValue: request.value,
      wIndex: request.index,
      wLength: request.length
    )
  }

  // IOUSBHost refuses a standard SET_INTERFACE sent as a device request (`kIOReturnNotPermitted`),
  // as DriverKit's `DeviceRequest` does (XPadMac `XPadGIPDevice.cpp`); `selectAlternateSetting`
  // sends it. Some third-party GIP pads wait for SET_INTERFACE(1, 0) before they start (#59).
  /// The interface and alternate setting that `request` selects when it is a standard
  /// SET_INTERFACE with no data stage, or nil for any other request.
  static func alternateSettingSelection(
    _ request: USBControlTransferRequest
  ) -> (interface: UInt8, setting: UInt8)? {
    guard request.kind == .standard, request.recipient == .interface, request.request == 0x0B,
      request.dataStage == .none, let interface = UInt8(exactly: request.index),
      let setting = UInt8(exactly: request.value)
    else { return nil }
    return (interface, setting)
  }

  /// IOUSBHost timeouts are seconds, where zero means no timeout.
  static func completionTimeout(milliseconds: UInt32) -> TimeInterval {
    TimeInterval(milliseconds) / 1_000
  }

  /// IOUSBHost requires a zero completion timeout for interrupt pipes; bulk pipes honor it.
  static func pipeCompletionTimeout(endpointAttributes: UInt8, milliseconds: UInt32) -> TimeInterval
  { endpointAttributes & 0x03 == 0x02 ? completionTimeout(milliseconds: milliseconds) : 0 }

  // An interrupt read on a silent pad never completes on its own, so without a host deadline the
  // input loop never sees a timeout and its silent-startup recovery never runs (#67).
  /// The host deadline in milliseconds after which a pending transfer is aborted, or nil when the
  /// pipe honors `milliseconds` itself or the caller asked for no timeout.
  static func hostDeadlineMilliseconds(endpointAttributes: UInt8, milliseconds: UInt32) -> UInt32? {
    pipeCompletionTimeout(endpointAttributes: endpointAttributes, milliseconds: milliseconds) == 0
      && milliseconds > 0 ? milliseconds : nil
  }

  /// Maps `error` to a transport error by its IOReturn code.
  static func transportError(_ error: any Error) -> USBTransportError {
    let nsError = error as NSError
    return transportError(IOReturn(truncatingIfNeeded: nsError.code))
  }

  /// Maps the IOReturn `code` to a transport error without an owner.
  static func transportError(_ code: IOReturn) -> USBTransportError {
    transportError(code, exclusiveOwner: nil)
  }

  /// `exclusiveOwner` is what the interface names when `code` says another client holds it.
  static func transportError(
    _ code: IOReturn,
    exclusiveOwner: String?
  ) -> USBTransportError {
    switch code {
    case kIOReturnTimeout, kIOReturnAborted: return .timeout
    case kIOReturnNoDevice, kIOReturnNotAttached, kIOReturnNotOpen, kIOReturnNotResponding:
      return .disconnected
    case kIOReturnExclusiveAccess: return .ownedByAnotherClient(owner: exclusiveOwner)
    case kIOReturnNotPermitted, kIOReturnNotPrivileged: return .accessDenied
    case kIOReturnNotFound: return .notFound
    case kIOReturnUnsupported, kIOReturnBadArgument: return .notSupported
    case kIOReturnIOError: return .inputOutput
    default: return .platform(code: code, message: String(describing: code))
    }
  }
}
