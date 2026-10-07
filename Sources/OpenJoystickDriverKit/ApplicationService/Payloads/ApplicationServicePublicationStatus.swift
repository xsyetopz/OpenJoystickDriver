/// Whether a virtual device publishes one controller, reported in
/// ``ApplicationServiceDeviceDescription``.
public struct ApplicationServicePublicationStatus: Codable, Equatable, Sendable {
  /// The publication state of a controller.
  public enum State: String, Codable, Equatable, Sendable {
    /// A virtual device is installed for the controller.
    case published
    /// No virtual device is installed; `reason` says why.
    case notPublished
    /// The last send to the virtual device failed; `reason` carries the failure.
    case failed
  }

  public let state: State
  /// Why the controller is not published: `outputDisabled`, `nativeGamepad`,
  /// `nativeHIDPassThrough`, `upstreamVirtualDevice`, `sessionSuspended`, `noVirtualProfile`,
  /// `suppressed`, or `noInputYet`; the failure text when `state` is `failed`; nil when
  /// published.
  public let reason: String?
  /// The virtual HID profile the controller publishes or tries to publish.
  public let target: VirtualHIDProfileID?
  /// System uptime in nanoseconds of the last send to the virtual device.
  public let lastAttemptedNanoseconds: UInt64?
  /// System uptime in nanoseconds of the last send the virtual device accepted.
  public let lastCompletedNanoseconds: UInt64?

  public init(
    state: State,
    reason: String? = nil,
    target: VirtualHIDProfileID? = nil,
    lastAttemptedNanoseconds: UInt64? = nil,
    lastCompletedNanoseconds: UInt64? = nil
  ) {
    self.state = state
    self.reason = reason
    self.target = target
    self.lastAttemptedNanoseconds = lastAttemptedNanoseconds
    self.lastCompletedNanoseconds = lastCompletedNanoseconds
  }
}
