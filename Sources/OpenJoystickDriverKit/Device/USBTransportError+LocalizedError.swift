public import Foundation

extension USBTransportError: LocalizedError {
  /// A sentence that names the failure, and the platform code of a ``platform(code:message:)``
  /// error, so a tool that prints `localizedDescription` shows the cause.
  public var errorDescription: String? {
    switch self {
    case .timeout: "The USB transfer timed out."
    case .disconnected: "The USB device disconnected."
    case .inputOutput: "The USB transfer failed with an input/output error."
    case .accessDenied: "The system denied access to the USB device."
    case .ownedByAnotherClient(let owner):
      "Another client holds the USB interface" + (owner.map { " (\($0))" } ?? "") + "."
    case .notFound: "The USB device, interface or endpoint was not found."
    case .notSupported: "The USB transport does not support this operation."
    case .platform(let code, let message): "USB platform error \(code): \(message)"
    }
  }
}
