import IOKit
import OpenJoystickDriverKit

extension PhysicalHIDFailure {
  /// `kIOUSBPipeStalled`: the device answered a control request with a STALL.
  private static let pipeStalled = IOReturn(bitPattern: 0xE000_404F)
  /// `kUSBHostReturnPipeStalled`: the IOUSBHost family's code for the same STALL, which a
  /// DualShock 3 clone returns for a feature report it does not have.
  private static let hostPipeStalled = IOReturn(bitPattern: 0xE000_5000)

  /// The failure an IOKit status code stands for.
  ///
  /// A device's own refusal (a stalled pipe or an unsupported request) is `declined`; a code
  /// without a name stays `hostStatus`.
  init(ioReturn code: IOReturn) {
    switch code {
    case kIOReturnTimeout: self = .timedOut
    case kIOReturnBusy: self = .busy
    case kIOReturnNotResponding: self = .notResponding
    case Self.pipeStalled, Self.hostPipeStalled, kIOReturnUnsupported: self = .declined
    default: self = .hostStatus(code)
    }
  }
}
