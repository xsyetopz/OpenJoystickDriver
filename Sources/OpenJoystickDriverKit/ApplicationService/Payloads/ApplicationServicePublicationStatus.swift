/// Whether a virtual device publishes one controller, reported in
/// ``ApplicationServiceDeviceDescription``.
public struct ApplicationServicePublicationStatus: Codable, Equatable, Sendable {
  /// The publication state of a controller.
  public enum State: String, Codable, Equatable, Sendable {
    /// A virtual device is installed for the controller.
    case published = "Published"
    /// No virtual device is installed; `reason` says why.
    case notPublished = "NotPublished"
    /// The last send to the virtual device failed; `failure` carries the text.
    case failed = "Failed"
  }

  /// Why a controller is not published.
  public enum NotPublishedReason: String, Codable, CaseIterable, Equatable, Sendable {
    /// Virtual output is off.
    case outputDisabled = "OutputDisabled"
    /// The system serves the controller as a gamepad.
    case systemGamepad = "SystemGamepad"
    /// The controller's native HID reports reach applications unchanged.
    case nativeHIDPassThrough = "NativeHIDPassThrough"
    /// Another virtual device already stands for the controller.
    case upstreamVirtualDevice = "UpstreamVirtualDevice"
    /// The user session of the controller is suspended.
    case sessionSuspended = "SessionSuspended"
    /// No persona can represent the controller's primary controls.
    case noVirtualProfile = "NoVirtualProfile"
    /// Remapping suppresses the virtual device.
    case suppressed = "Suppressed"
    /// The controller has sent no input yet.
    case noInputYet = "NoInputYet"
    /// Another client holds the controller's input, so a virtual device would never move; OJD
    /// publishes once the client lets go.
    case heldByAnotherClient = "HeldByAnotherClient"
  }

  /// Whether the controller is published, and how its last send ended.
  public let state: State
  /// Why the controller is not published; set exactly when `state` is `NotPublished`.
  public let reason: NotPublishedReason?
  /// The text of the failed send, never empty; set exactly when `state` is `Failed`.
  public let failure: String?
  /// The virtual HID profile the controller publishes or tries to publish.
  public let target: VirtualHIDProfileID?
  /// System uptime in nanoseconds of the last send to the virtual device.
  public let lastAttemptedNanoseconds: UInt64?
  /// System uptime in nanoseconds of the last send the virtual device accepted.
  public let lastCompletedNanoseconds: UInt64?

  /// Creates a status; the public factories pass the combination of values each state allows.
  private init(
    state: State,
    reason: NotPublishedReason?,
    failure: String?,
    target: VirtualHIDProfileID?,
    lastAttemptedNanoseconds: UInt64?,
    lastCompletedNanoseconds: UInt64?
  ) {
    self.state = state
    self.reason = reason
    self.failure = failure
    self.target = target
    self.lastAttemptedNanoseconds = lastAttemptedNanoseconds
    self.lastCompletedNanoseconds = lastCompletedNanoseconds
  }

  /// A virtual device is installed for the controller.
  public static func published(
    target: VirtualHIDProfileID? = nil,
    lastAttemptedNanoseconds: UInt64? = nil,
    lastCompletedNanoseconds: UInt64? = nil
  ) -> Self {
    Self(
      state: .published,
      reason: nil,
      failure: nil,
      target: target,
      lastAttemptedNanoseconds: lastAttemptedNanoseconds,
      lastCompletedNanoseconds: lastCompletedNanoseconds
    )
  }

  /// No virtual device is installed, for `reason`.
  public static func notPublished(
    _ reason: NotPublishedReason,
    target: VirtualHIDProfileID? = nil,
    lastAttemptedNanoseconds: UInt64? = nil,
    lastCompletedNanoseconds: UInt64? = nil
  ) -> Self {
    Self(
      state: .notPublished,
      reason: reason,
      failure: nil,
      target: target,
      lastAttemptedNanoseconds: lastAttemptedNanoseconds,
      lastCompletedNanoseconds: lastCompletedNanoseconds
    )
  }

  /// The last send failed with `failure`, which is not empty.
  public static func failed(
    _ failure: String,
    target: VirtualHIDProfileID? = nil,
    lastAttemptedNanoseconds: UInt64? = nil,
    lastCompletedNanoseconds: UInt64? = nil
  ) -> Self {
    precondition(!failure.isEmpty, "A failed publication carries its failure text.")
    return Self(
      state: .failed,
      reason: nil,
      failure: failure,
      target: target,
      lastAttemptedNanoseconds: lastAttemptedNanoseconds,
      lastCompletedNanoseconds: lastCompletedNanoseconds
    )
  }

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey {
    /// The `state` key.
    case state
    /// The `reason` key.
    case reason
    /// The `failure` key.
    case failure
    /// The `target` key.
    case target
    /// The `lastAttemptedNanoseconds` key.
    case lastAttemptedNanoseconds
    /// The `lastCompletedNanoseconds` key.
    case lastCompletedNanoseconds
  }

  /// Refuses a payload whose `reason` or `failure` does not match its `state`, and an empty
  /// `failure`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedState = try container.decode(State.self, forKey: .state)
    let decodedReason = try container.decodeIfPresent(NotPublishedReason.self, forKey: .reason)
    let decodedFailure = try container.decodeIfPresent(String.self, forKey: .failure)
    switch decodedState {
    case .published:
      guard decodedReason == nil, decodedFailure == nil else {
        throw Self.mismatch(container, "A Published publication has no reason or failure.")
      }
    case .notPublished:
      guard decodedReason != nil, decodedFailure == nil else {
        throw Self.mismatch(container, "A NotPublished publication has a reason and no failure.")
      }
    case .failed:
      guard decodedReason == nil, let decodedFailure, !decodedFailure.isEmpty else {
        throw Self.mismatch(container, "A Failed publication has a failure text and no reason.")
      }
    }
    self.init(
      state: decodedState,
      reason: decodedReason,
      failure: decodedFailure,
      target: try container.decodeIfPresent(VirtualHIDProfileID.self, forKey: .target),
      lastAttemptedNanoseconds: try container.decodeIfPresent(
        UInt64.self,
        forKey: .lastAttemptedNanoseconds
      ),
      lastCompletedNanoseconds: try container.decodeIfPresent(
        UInt64.self,
        forKey: .lastCompletedNanoseconds
      )
    )
  }

  /// Builds the decoding error for a combination of values that the `state` does not allow.
  private static func mismatch(
    _ container: KeyedDecodingContainer<CodingKeys>,
    _ description: String
  ) -> DecodingError {
    DecodingError.dataCorruptedError(
      forKey: .state,
      in: container,
      debugDescription: description
    )
  }
}
