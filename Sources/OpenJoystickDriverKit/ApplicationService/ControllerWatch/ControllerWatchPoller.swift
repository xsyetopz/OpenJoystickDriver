import Foundation

/// A controller as a watch line carries it: the `Controller` object with the fields of a
/// ``ControllerSummary``, and the last input and output once the controller has any.
public struct WatchedController: Encodable, Equatable, Sendable {
  /// The `kind` of a watched controller object.
  public static let kind = "Controller"

  /// The fields of the controller list entry.
  public var summary: ControllerSummary
  /// The controller's last input; nil until the controller has sent input.
  public var input: ControllerState?
  /// Present while a virtual gamepad publishes the controller and the watch asked for output.
  public var output: ApplicationServiceVirtualOutputState?

  /// The ID from `ojd controller list`.
  public var id: String { summary.id }

  /// Creates a watched controller from a summary, its input and its output.
  public init(
    summary: ControllerSummary,
    input: ControllerState? = nil,
    output: ApplicationServiceVirtualOutputState? = nil
  ) {
    self.summary = summary
    self.input = input
    self.output = output
  }

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey {
    /// The `apiVersion` key.
    case apiVersion
    /// The `kind` key.
    case kind
    /// The `input` key.
    case input
    /// The `output` key.
    case output
  }

  /// Encodes the value into `encoder`.
  public func encode(to encoder: any Encoder) throws {
    try summary.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(OpenJoystickDriverAPI.version, forKey: .apiVersion)
    try container.encode(Self.kind, forKey: .kind)
    try container.encodeIfPresent(input, forKey: .input)
    try container.encodeIfPresent(output, forKey: .output)
  }
}

/// One line of `ojd controller watch --all` and of the endpoint's `Controllers` stream, shaped
/// like a Kubernetes watch event: `{"type":"ADDED","object":{...}}`.
///
/// The line has no `apiVersion` and `kind` of its own; its `object` does.
public struct ControllerWatchEvent: Encodable, Equatable, Sendable {
  /// The type of watch event.
  public enum Kind: String, Encodable, Sendable {
    /// A controller connected, or was connected when the watch started.
    case added = "ADDED"
    /// The controller's input, or with output, its virtual gamepad's values, changed.
    case modified = "MODIFIED"
    /// The controller disconnected; the object is the last one the watch saw.
    case deleted = "DELETED"
  }

  /// What happened to the controller.
  public let type: Kind
  /// The controller the event is about.
  public var object: WatchedController

  /// The ID from `ojd controller list`.
  public var id: String { object.id }

  /// Creates an event from its type and controller.
  public init(type: Kind, object: WatchedController) {
    self.type = type
    self.object = object
  }
}

/// Where a ``ControllerWatchPoller`` reads controllers: the service socket or the service itself.
public protocol ControllerWatchSource: Sendable {
  /// The connected controllers.
  func devices() async throws -> [ApplicationServiceDeviceDescription]
  /// Nil when the controller has no input state yet.
  func state(of device: ApplicationServiceDeviceDescription) async throws -> ControllerState?
  /// Nil when no virtual gamepad publishes the controller.
  func output(
    of device: ApplicationServiceDeviceDescription
  ) async throws
    -> ApplicationServiceVirtualOutputState?
}

/// Turns repeated reads of every controller into connection and input-change events.
public struct ControllerWatchPoller {
  /// One event and the controller it is about.
  public struct Update {
    /// The event to report.
    public let event: ControllerWatchEvent
    /// The controller the event is about.
    public let device: ApplicationServiceDeviceDescription
  }

  /// How often the poller reads the list of connected controllers.
  public static let deviceListInterval: UInt64 = 250_000_000
  /// How long callers wait between polls.
  public static let pollInterval: UInt64 = 16_000_000

  /// The input and output of a controller at one poll.
  private struct Sample: Equatable {
    /// The controller's input.
    let input: ControllerState
    /// The virtual gamepad's output; nil when the poll did not read it.
    let output: ApplicationServiceVirtualOutputState?
  }

  /// Where the poller reads controllers.
  private let source: any ControllerWatchSource
  /// The controllers connected at the last list read.
  private var connected: [ApplicationServiceDeviceDescription] = []
  /// The last sample of each connected controller.
  private var previous: [ControllerSessionToken: Sample] = [:]
  /// The latest object of each connected controller, which a `DELETED` line carries.
  private var objects: [ControllerSessionToken: WatchedController] = [:]
  /// The uptime of the last list read, in nanoseconds.
  private var listedAt: UInt64?

  /// Creates a poller that reads from `source`.
  public init(source: any ControllerWatchSource) { self.source = source }

  /// Reads the controllers once and returns what changed since the last poll.
  ///
  /// The first poll reports an `ADDED` event for each controller already connected. `now` is
  /// an uptime in nanoseconds; the controller list is read again once `deviceListInterval` passed.
  public mutating func poll(now: UInt64, includeOutput: Bool) async throws -> [Update] {
    var updates: [Update] = []
    if listedAt.map({ now - $0 >= Self.deviceListInterval }) ?? true {
      listedAt = now
      let devices = try await source.devices()
      let ids = Set(devices.map(\.sessionToken))
      for device in connected where !ids.contains(device.sessionToken) {
        previous[device.sessionToken] = nil
        let last = objects.removeValue(forKey: device.sessionToken)
        let object = last ?? WatchedController(summary: ControllerSummary(device))
        updates.append(
          Update(event: ControllerWatchEvent(type: .deleted, object: object), device: device)
        )
      }
      let known = Set(connected.map(\.sessionToken))
      for device in devices where !known.contains(device.sessionToken) {
        let object = WatchedController(summary: ControllerSummary(device))
        objects[device.sessionToken] = object
        updates.append(
          Update(event: ControllerWatchEvent(type: .added, object: object), device: device)
        )
      }
      connected = devices
    }
    for device in connected {
      // The output is built from the input after it, so reading it first keeps it from showing a
      // value before the input that produced it.
      let output = includeOutput ? try await source.output(of: device) : nil
      guard let input = try await source.state(of: device) else { continue }
      let sample = Sample(input: input, output: output)
      guard sample != previous[device.sessionToken] else { continue }
      previous[device.sessionToken] = sample
      let object = WatchedController(
        summary: ControllerSummary(device),
        input: input,
        output: output
      )
      objects[device.sessionToken] = object
      updates.append(
        Update(event: ControllerWatchEvent(type: .modified, object: object), device: device)
      )
    }
    return updates
  }
}
