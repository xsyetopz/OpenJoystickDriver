public import Foundation

/// One canonical frame on the streaming boundary.
///
/// A frame is a value, not a transport: it carries no socket, no HID handle, and no platform
/// type. The same three shapes travel the boundary wherever a source and a sink meet.
public enum StreamFrame: Sendable {
  /// A controller's parsed state and its motion and touch samples, before any user mapping.
  case controller(ControllerEvent, from: LogicalControllerID)
  /// A virtual gamepad's state after mapping, or a feed client's frame.
  case gamepad(RemappingGamepadState, for: LogicalControllerID)
  /// An observed controller snapshot change, as the endpoint's `Controllers` stream carries it.
  case observed(ControllerWatchEvent)
  /// One frame of a feed client with its hold, before it plays on the feed's virtual gamepad.
  case feed(VirtualFeedFrame)
  /// A request to make a controller's output exist, such as its virtual device, with no new input.
  case activation(LogicalControllerID)
}

/// One remapping claim on a physical controller's output: it holds `output` while `active`, and
/// the claim's `owner` releases it.
public struct MappingOutputClaim: Equatable, Sendable {
  /// The output that the claim holds.
  public let output: RemappingPhysicalOutput
  /// Whether the claim holds the output.
  public let active: Bool
  /// The owner of the claim, which releases it.
  public let owner: UUID

  /// Creates a claim on `output` for `owner`.
  public init(_ output: RemappingPhysicalOutput, active: Bool, owner: UUID) {
    self.output = output
    self.active = active
    self.owner = owner
  }
}

/// The release of every remapping claim on one physical controller's output.
public struct MappingOutputRelease: Equatable, Sendable {
  /// Creates a release.
  public init() {}
}

/// The profile's color for one physical controller, or nil to remove it.
public struct ProfileColorClaim: Equatable, Sendable {
  /// The color; nil removes the color.
  public let color: ControllerColor?

  /// Creates a claim for `color`.
  public init(_ color: ControllerColor?) { self.color = color }
}

/// Where an ``InputSource`` gets its frames.
public enum InputOrigin: String, CaseIterable, Sendable {
  /// A physical controller read and parsed by a protocol driver.
  case physicalController
  /// A client of a local virtual feed, such as `ojd virtual feed`.
  case virtualFeed
  /// A client of the endpoint's `FeedRequest`.
  case endpointFeed
  /// The poll of controller state that the endpoint's `Subscription` streams.
  case endpointStream
}

/// What an ``OutputSink`` does with what it consumes.
public enum OutputDestination: String, CaseIterable, Sendable {
  /// A virtual HID gamepad that games and apps see.
  case virtualDevice
  /// A client subscribed to the endpoint's `Controllers` stream.
  case endpointSubscription
  /// A client of the endpoint's `FeedRequest`, which receives the host's rumble commands.
  case endpointFeedClient
  /// Output commands, such as rumble and lights, written to a physical controller.
  case physicalOutput
  /// A log line, for development.
  case diagnosticLog
}

/// Why a sink refused what it was given.
public enum StreamBoundaryError: Error, Equatable, Sendable {
  /// The sink consumes no frame of this shape, or no output command.
  case unsupported(OutputDestination)
  /// The controller or the device behind the sink is gone, or refused the command.
  case rejected(OutputDestination, String)
}

/// A producer of canonical frames: a physical controller, an endpoint feed, a virtual feed.
///
/// A source delivers every frame to its ``sink`` through ``produce(_:onDelivered:)``; it never
/// reaches around the sink. Sources are compiled in, and OJD loads no code at run time. The
/// protocol imports nothing from a platform, so a Linux or Windows source conforms the same way.
public protocol InputSource: AnyObject, Sendable {
  /// Which kind of path this source is.
  var origin: InputOrigin { get }
  /// Where this source's frames go.
  var sink: any OutputSink { get }
}

extension InputSource {
  /// Sends one frame to ``sink``. `onDelivered` runs once the frame reached the sink's
  /// destination, which is where the pipeline stamps a delivery stage; it does not run for a frame
  /// the sink suppresses or fails to deliver.
  @preconcurrency
  public func produce(
    _ frame: StreamFrame,
    onDelivered: @escaping @Sendable () -> Void = {}
  ) async throws {
    try await sink.consume(frame, onDelivered: onDelivered)
  }
}

/// A consumer of canonical frames or output commands: a virtual device, an endpoint subscription,
/// a physical controller's output.
///
/// A sink takes only the shapes it supports and throws ``StreamBoundaryError/unsupported(_:)`` for
/// the rest; the defaults do exactly that.
public protocol OutputSink: AnyObject, Sendable {
  /// Which kind of path this sink is.
  var destination: OutputDestination { get }

  /// Consumes one frame. `onDelivered` runs once the frame reached the destination, and not for a
  /// frame the sink suppresses or fails to deliver.
  @preconcurrency
  func consume(
    _ frame: StreamFrame,
    onDelivered: @escaping @Sendable () -> Void
  ) async throws

  /// Consumes one output command, such as rumble or a light, for one controller.
  func consume(
    _ command: ControllerOutputCommand,
    for controller: LogicalControllerID
  )
    async throws

  /// Consumes one remapping claim on a physical controller's output.
  func consume(_ claim: MappingOutputClaim, for controller: LogicalControllerID) async throws

  /// Releases every remapping claim on a physical controller's output.
  func consume(_ release: MappingOutputRelease, for controller: LogicalControllerID) async throws

  /// Sets or removes the profile's color on a physical controller.
  func consume(_ color: ProfileColorClaim, for controller: LogicalControllerID) async throws
}

// swiftlint:disable async_without_await
extension OutputSink {
  /// Refuses the frame, because the sink consumes no frame.
  ///
  /// - Throws: ``StreamBoundaryError/unsupported(_:)``.
  @preconcurrency
  public func consume(
    _: StreamFrame,
    onDelivered _: @Sendable () -> Void
  ) async throws {
    throw StreamBoundaryError.unsupported(destination)
  }

  /// Refuses the command, because the sink consumes no output command.
  ///
  /// - Throws: ``StreamBoundaryError/unsupported(_:)``.
  public func consume(
    _: ControllerOutputCommand,
    for _: LogicalControllerID
  )
    async throws
  {
    throw StreamBoundaryError.unsupported(destination)
  }

  /// Refuses the claim, because the sink consumes no mapping claim.
  ///
  /// - Throws: ``StreamBoundaryError/unsupported(_:)``.
  public func consume(_: MappingOutputClaim, for _: LogicalControllerID) async throws {
    throw StreamBoundaryError.unsupported(destination)
  }

  /// Refuses the release, because the sink consumes no mapping release.
  ///
  /// - Throws: ``StreamBoundaryError/unsupported(_:)``.
  public func consume(
    _: MappingOutputRelease,
    for _: LogicalControllerID
  ) async throws {
    throw StreamBoundaryError.unsupported(destination)
  }

  /// Refuses the color, because the sink consumes no profile color.
  ///
  /// - Throws: ``StreamBoundaryError/unsupported(_:)``.
  public func consume(
    _: ProfileColorClaim,
    for _: LogicalControllerID
  ) async throws {
    throw StreamBoundaryError.unsupported(destination)
  }
}
// swiftlint:enable async_without_await
