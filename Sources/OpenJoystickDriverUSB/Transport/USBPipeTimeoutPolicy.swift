import IOKit
import OpenJoystickDriverKit

/// Chooses the completion timeout of a transfer on an endpoint.
///
/// `IOUSBHostPipe::IO` answers `kIOReturnBadArgument` to any timeout but 0 on an interrupt pipe
/// (#55), so an interrupt endpoint gets 0 whatever the caller asks for.
actor USBPipeTimeoutPolicy {
  /// The `bmAttributes` transfer-type mask and the value of an interrupt endpoint.
  private static let transferTypeMask: UInt8 = 0x03
  private static let interruptTransfer: UInt8 = 0x03

  /// Returns the `bmAttributes` of an endpoint.
  private let attributes: @Sendable (UInt8) async throws -> UInt8
  /// Whether each endpoint read so far is an interrupt endpoint.
  private var isInterrupt: [UInt8: Bool] = [:]

  /// Creates the policy over `attributes`, which reads an endpoint's `bmAttributes`.
  init(attributes: @escaping @Sendable (UInt8) async throws -> UInt8) {
    self.attributes = attributes
  }

  /// Returns 0 on an interrupt endpoint and `requestedMilliseconds` on any other, and also when the
  /// endpoint's type cannot be read, which is asked again on the next transfer.
  func timeout(endpoint: UInt8, requestedMilliseconds: UInt32) async -> UInt32 {
    if let known = isInterrupt[endpoint] { return known ? 0 : requestedMilliseconds }
    guard let value = try? await attributes(endpoint) else { return requestedMilliseconds }
    let interrupt = value & Self.transferTypeMask == Self.interruptTransfer
    isInterrupt[endpoint] = interrupt
    return interrupt ? 0 : requestedMilliseconds
  }
}
