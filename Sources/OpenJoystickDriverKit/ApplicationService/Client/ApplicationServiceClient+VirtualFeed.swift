public import Foundation

extension ApplicationServiceClient {
  /// Publishes a virtual controller with the `profile` virtual HID profile, such as `Generic`,
  /// that this client drives with ``exchangeVirtualFeed(token:frames:)``.
  ///
  /// Only OpenJoystickDriver's own signed executables can call this; other programs use
  /// `ojd virtual feed`.
  public func openVirtualFeed(profile: String) async throws -> VirtualFeedSession {
    try await call(.openVirtualFeed, LocalServiceRPCVirtualFeedOpenArguments(profile: profile))
  }

  /// Queues `frames` on the feed and returns the output commands queued since the previous
  /// exchange.
  ///
  /// Send the frames past ``VirtualFeedExchangeResult/accepted`` again later. Exchange at least
  /// every ``VirtualFeedExchangeResult/idleTimeoutSeconds`` to keep the feed open.
  ///
  /// Only OpenJoystickDriver's own signed executables can call this; other programs use
  /// `ojd virtual feed`.
  public func exchangeVirtualFeed(
    token: UUID,
    frames: [VirtualFeedFrame] = []
  ) async throws -> VirtualFeedExchangeResult {
    try await call(
      .exchangeVirtualFeed,
      LocalServiceRPCVirtualFeedExchangeArguments(token: token, frames: frames)
    )
  }

  /// Waits up to `timeoutMilliseconds` until an exchange with the feed has something to report: a
  /// host output command or the feed's closure; returns true when it does.
  ///
  /// The wait collects nothing, so an exchange after it returns the commands in the order the
  /// host sent them. It does not keep the feed open. The service caps the wait at
  /// ``LocalServiceRPCVirtualFeedWaitArguments/maximumTimeoutMilliseconds``.
  ///
  /// Only OpenJoystickDriver's own signed executables can call this; other programs use
  /// `ojd virtual feed`.
  public func waitForVirtualFeedFeedback(
    token: UUID,
    timeoutMilliseconds: Int
  ) async throws -> Bool {
    let capped = min(
      max(0, timeoutMilliseconds),
      LocalServiceRPCVirtualFeedWaitArguments.maximumTimeoutMilliseconds
    )
    return try await call(
      .waitForVirtualFeedFeedback,
      LocalServiceRPCVirtualFeedWaitArguments(token: token, timeoutMilliseconds: capped),
      timeoutSeconds: TimeInterval(capped) / 1000 + applicationServiceDefaultReplyTimeoutSeconds,
      closedWithoutReply: .serviceClosedConnection
    )
  }

  /// Removes the feed's virtual controller; false when no open feed has the token.
  ///
  /// Only OpenJoystickDriver's own signed executables can call this; other programs use
  /// `ojd virtual feed`.
  @discardableResult
  public func closeVirtualFeed(token: UUID) async throws -> Bool {
    try await call(.closeVirtualFeed, LocalServiceRPCVirtualFeedCloseArguments(token: token))
  }
}
