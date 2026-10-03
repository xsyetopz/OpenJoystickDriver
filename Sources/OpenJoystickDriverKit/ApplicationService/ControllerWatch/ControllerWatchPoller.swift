import Foundation

/// One line of `ojd controller watch --all` and of the endpoint's `controllers` stream.
public struct ControllerWatchEvent: Encodable, Equatable, Sendable {
  public enum Kind: String, Encodable, Sendable {
    case connected
    case input
    case disconnected
  }

  public let type: Kind
  /// The ID from `ojd controller list`.
  public let id: String
  /// Present on `connected` lines.
  public var controller: ControllerSummary?
  /// Present on `input` lines.
  public var input: ControllerState?
  /// Present on `input` lines that asked for output while a virtual gamepad publishes the
  /// controller.
  public var output: ApplicationServiceVirtualOutputState?

  public init(
    type: Kind,
    id: String,
    controller: ControllerSummary? = nil,
    input: ControllerState? = nil,
    output: ApplicationServiceVirtualOutputState? = nil
  ) {
    self.type = type
    self.id = id
    self.controller = controller
    self.input = input
    self.output = output
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
  private var listedAt: UInt64?

  public init(source: any ControllerWatchSource) { self.source = source }

  /// Reads the controllers once and returns what changed since the last poll.
  ///
  /// The first poll reports a `connected` event for each controller already connected. `now` is
  /// an uptime in nanoseconds; the controller list is read again once `deviceListInterval` passed.
  public mutating func poll(now: UInt64, includeOutput: Bool) async throws -> [Update] {
    var updates: [Update] = []
    if listedAt.map({ now - $0 >= Self.deviceListInterval }) ?? true {
      listedAt = now
      let devices = try await source.devices()
      let ids = Set(devices.map(\.runtimeIdentifier))
      for device in connected where !ids.contains(device.runtimeIdentifier) {
        previous[device.runtimeIdentifier] = nil
        updates.append(
          Update(
            event: ControllerWatchEvent(type: .disconnected, id: device.runtimeIdentifier),
            device: device
          )
        )
      }
      let known = Set(connected.map(\.runtimeIdentifier))
      for device in devices where !known.contains(device.runtimeIdentifier) {
        let event = ControllerWatchEvent(
          type: .connected,
          id: device.runtimeIdentifier,
          controller: ControllerSummary(device)
        )
        updates.append(Update(event: event, device: device))
      }
      connected = devices
    }
    for device in connected {
      guard let input = try await source.state(of: device) else { continue }
      let output = includeOutput ? try await source.output(of: device) : nil
      let sample = Sample(input: input, output: output)
      guard sample != previous[device.runtimeIdentifier] else { continue }
      previous[device.runtimeIdentifier] = sample
      let event = ControllerWatchEvent(
        type: .input,
        id: device.runtimeIdentifier,
        input: input,
        output: output
      )
      updates.append(Update(event: event, device: device))
    }
    return updates
  }
}
