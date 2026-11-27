public import Foundation

extension USBTransportError: LocalizedError {
  /// A sentence that names the failure, and the platform code of a ``platform(code:message:)``
  /// error, so a tool that prints `localizedDescription` shows the cause.
  public var errorDescription: String? {
    let localized = Localization()
    return switch self {
    case .timeout: localized.string("ui.usbTransport.timeout")
    case .disconnected: localized.string("ui.usbTransport.disconnected")
    case .inputOutput: localized.string("ui.usbTransport.inputOutput")
    case .accessDenied: localized.string("ui.usbTransport.accessDenied")
    case .ownedByAnotherClient(let owner):
      owner.map { localized.string("ui.usbTransport.ownedByNamedClient", $0) }
        ?? localized.string("ui.usbTransport.ownedByAnotherClient")
    case .notFound: localized.string("ui.usbTransport.notFound")
    case .notSupported: localized.string("ui.usbTransport.notSupported")
    case .platform(let code, let message):
      localized.string("ui.usbTransport.platform", String(code), message)
    }
  }
}
