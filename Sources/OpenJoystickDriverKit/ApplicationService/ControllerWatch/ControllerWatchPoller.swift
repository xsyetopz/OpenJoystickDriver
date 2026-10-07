import Foundation

/// A controller as a watch line carries it: the `Controller` object with the fields of a
/// ``ControllerSummary``, and the last input and output once the controller has any.
public struct WatchedController: Encodable, Equatable, Sendable {
  public static let kind = "Controller"

  public var summary: ControllerSummary
  public var input: ControllerState?
  /// Present while a virtual gamepad publishes the controller and the watch asked for output.
  public var output: ApplicationServiceVirtualOutputState?

  /// The ID from `ojd controller list`.
  public var id: String { summary.id }

  public init(
    summary: ControllerSummary,
    input: ControllerState? = nil,
    output: ApplicationServiceVirtualOutputState? = nil
  ) {
    self.summary = summary
    self.input = input
    self.output = output
  }

  private enum CodingKeys: String, CodingKey {
    case apiVersion
    case kind
    case input
    case output
  }

  public func encode(to encoder: any Encoder) throws {
    try summary.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(OpenJoystickDriverAPI.version, forKey: .apiVersion)
    try container.encode(Self.kind, forKey: .kind)
    try container.encodeIfPresent(input, forKey: .input)
    try container.encodeIfPresent(output, forKey: .output)
  }
}

/// One line of `ojd controller watch --all` and of the endpoint's `controllers` stream, shaped
/// like a Kubernetes watch event: `{"type":"ADDED","object":{...}}`.
///
/// The line has no `apiVersion` and `kind` of its own; its `object` does.
public struct ControllerWatchEvent: Encodable, Equatable, Sendable {
  public enum Kind: String, Encodable, Sendable {
    /// A controller connected, or was connected when the watch started.
    case added = "ADDED"
    /// The controller's input, or with output, its virtual gamepad's values, changed.
    case modified = "MODIFIED"
    /// The controller disconnected; the object is the last one the watch saw.
    case deleted = "DELETED"
  }

  public let type: Kind
  public var object: WatchedController

  /// The ID from `ojd controller list`.
  public var id: String { object.id }

  public init(type: Kind, object: WatchedController) {
    self.type = type
    self.object = object
  }
}

/// Where a ``ControllerWatchPoller`` reads controllers: the service socket or the service itself.
public protocol ControllerWatchSource: Sendable {
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
    public let event: ControllerWatchEvent
    public let device: ApplicationServiceDeviceDescription
  }

  /// How often the poller reads the list of connected controllers.
  public static let deviceListInterval: UInt64 = 250_000_000
  /// How long callers wait between polls.
  public static let pollInterval: UInt64 = 16_000_000

  private struct Sample: Equatable {
    let input: ControllerState
    let output: ApplicationServiceVirtualOutputState?
  }

  private let source: any ControllerWatchSource
  private var connected: [ApplicationServiceDeviceDescription] = []
  private var previous: [String: Sample] = [:]
  /// The latest object of each connected controller, which a `DELETED` line carries.
  private var objects: [String: WatchedController] = [:]
  private var listedAt: UInt64?

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
      let ids = Set(devices.map(\.runtimeIdentifier))
      for device in connected where !ids.contains(device.runtimeIdentifier) {
        previous[device.runtimeIdentifier] = nil
        let last = objects.removeValue(forKey: device.runtimeIdentifier)
        let object = last ?? WatchedController(summary: ControllerSummary(device))
        updates.append(
          Update(event: ControllerWatchEvent(type: .deleted, object: object), device: device)
        )
      }
      let known = Set(connected.map(\.runtimeIdentifier))
      for device in devices where !known.contains(device.runtimeIdentifier) {
        let object = WatchedController(summary: ControllerSummary(device))
        objects[device.runtimeIdentifier] = object
        updates.append(
          Update(event: ControllerWatchEvent(type: .added, object: object), device: device)
        )
      }
      connected = devices
    }
    for device in connected {
      guard let input = try await source.state(of: device) else { continue }
      let output = includeOutput ? try await source.output(of: device) : nil
      let sample = Sample(input: input, output: output)
      guard sample != previous[device.runtimeIdentifier] else { continue }
      previous[device.runtimeIdentifier] = sample
      let object = WatchedController(
        summary: ControllerSummary(device),
        input: input,
        output: output
      )
      objects[device.runtimeIdentifier] = object
      updates.append(
        Update(event: ControllerWatchEvent(type: .modified, object: object), device: device)
      )
    }
    return updates
  }
}
