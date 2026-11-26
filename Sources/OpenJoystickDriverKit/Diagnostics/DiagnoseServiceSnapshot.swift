import Foundation

/// What the service reported, or why it could not.
public struct DiagnoseServiceSnapshot: Sendable {
  /// Whether the service answered.
  public enum Availability: Sendable, Equatable {
    /// The service answered.
    case running
    /// The service is not running.
    case stopped
    /// The service failed to answer the status request; the value is the message to show.
    case failed(String)
  }

  /// Whether the service answered.
  public let availability: Availability
  /// The service status; nil unless the service is running.
  public let status: ApplicationServiceStatusPayload?
  /// The diagnostics of the virtual devices; nil when the service did not answer that request.
  public let virtualDiagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload?
  /// The frame timings; nil when the service did not answer that request.
  public let frameTimings: ApplicationServiceFrameTimingsPayload?
  /// The record of why the service's request listener stopped; only read while the service is
  /// stopped.
  public let listenerFailure: ServiceListenerFailure.Reading

  /// Creates a snapshot from its values.
  public init(
    availability: Availability,
    status: ApplicationServiceStatusPayload?,
    virtualDiagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload?,
    frameTimings: ApplicationServiceFrameTimingsPayload?,
    listenerFailure: ServiceListenerFailure.Reading
  ) {
    self.availability = availability
    self.status = status
    self.virtualDiagnostics = virtualDiagnostics
    self.frameTimings = frameTimings
    self.listenerFailure = listenerFailure
  }
}

extension DiagnoseServiceSnapshot {
  /// Asks the service once; a stopped or failing service never throws.
  ///
  /// `classify` turns the error
  /// of a failed status request into the availability; ``availability(after:)`` is the rule for
  /// the Kit client errors. A stopped service gets `listenerFailure`, the record of why its
  /// request listener stopped.
  @preconcurrency
  public static func gather(
    status: @Sendable () async throws -> ApplicationServiceStatusPayload,
    virtualDiagnostics:
      @Sendable () async throws -> ApplicationServiceVirtualDeviceDiagnosticsPayload,
    frameTimings: @Sendable () async throws -> ApplicationServiceFrameTimingsPayload,
    classify: @Sendable (any Error) -> Availability = { availability(after: $0) },
    listenerFailure: @Sendable () -> ServiceListenerFailure.Reading
  ) async -> Self {
    do {
      let payload = try await status()
      return Self(
        availability: .running,
        status: payload,
        virtualDiagnostics: try? await virtualDiagnostics(),
        frameTimings: try? await frameTimings(),
        listenerFailure: .absent
      )
    } catch {
      let availability = classify(error)
      return Self(
        availability: availability,
        status: nil,
        virtualDiagnostics: nil,
        frameTimings: nil,
        listenerFailure: availability == .stopped ? listenerFailure() : .absent
      )
    }
  }

  /// An unreachable service is stopped; any other error leaves it failed, with the message that
  /// the command-line tool gives for a failed request.
  public static func availability(after error: any Error) -> Availability {
    if case ApplicationServiceClientError.notConnected = error { return .stopped }
    let detail = error.localizedDescription
    return .failed(
      Localization().formatted(
        "cli.shared.error.serviceRequestFailed",
        arguments: [detail.hasSuffix(".") ? String(detail.dropLast()) : detail]
      )
    )
  }
}
