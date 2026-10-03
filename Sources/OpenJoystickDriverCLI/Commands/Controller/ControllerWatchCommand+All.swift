import Foundation
import OpenJoystickDriverKit

extension ControllerWatchCommand {
  /// One line of `ojd controller watch --all`.
  struct Event: Encodable, Equatable {
    enum Kind: String, Encodable {
      case connected
      case input
      case disconnected
    }

    let type: Kind
    /// The ID from `ojd controller list`.
    let id: String
    /// Present on `connected` lines.
    var controller: ControllerSummary?
    /// Present on `input` lines.
    var input: ControllerState?
    /// Present on `input` lines with --output while a virtual gamepad publishes the controller.
    var output: ApplicationServiceVirtualOutputState?
  }

  /// How often `--all` reads the list of connected controllers.
  static let deviceListInterval: UInt64 = 250_000_000

  /// Prints a `connected` line for each controller already connected, then input and connection
  /// changes for every controller until `duration` elapses or the command is interrupted.
  func watchAll() async throws {
    let client = try await ServiceConnection.open()
    defer { client.disconnect() }
    let timeout = CLIContext.current.requestTimeout
    if CLIContext.current.format == .human {
      CLIOutput.success(
        CLILocalized.text(
          "cli.controller.watch.all_started",
          "Watching every controller. Press controller buttons."
        )
      )
    }
    var connected: [ApplicationServiceDeviceDescription] = []
    var previous: [String: Sample] = [:]
    var listedAt: UInt64?
    _ = try await pollController(duration: duration) {
      let now = DispatchTime.now().uptimeNanoseconds
      if listedAt.map({ now - $0 >= Self.deviceListInterval }) ?? true {
        listedAt = now
        let devices = try await ServiceConnection.withDeadline(seconds: timeout) {
          try await client.getStatus().connectedDevices
        }
        let ids = Set(devices.map(\.runtimeIdentifier))
        for device in connected where !ids.contains(device.runtimeIdentifier) {
          previous[device.runtimeIdentifier] = nil
          try emit(Event(type: .disconnected, id: device.runtimeIdentifier), device: device)
        }
        let known = Set(connected.map(\.runtimeIdentifier))
        for device in devices where !known.contains(device.runtimeIdentifier) {
          let event = Event(
            type: .connected,
            id: device.runtimeIdentifier,
            controller: ControllerSummary(device)
          )
          try emit(event, device: device)
        }
        connected = devices
      }
      for device in connected {
        guard let sample = try await read(device, client: client, timeout: timeout),
          sample != previous[device.runtimeIdentifier]
        else { continue }
        previous[device.runtimeIdentifier] = sample
        let event = Event(
          type: .input,
          id: device.runtimeIdentifier,
          input: sample.input,
          output: sample.output
        )
        try emit(event, device: device)
      }
      return false
    }
  }

  private func read(
    _ device: ApplicationServiceDeviceDescription,
    client: ApplicationServiceClient,
    timeout: Double
  ) async throws -> Sample? {
    let output = output
    return try await ServiceConnection.withDeadline(seconds: timeout) {
      guard
        let input = try await client.controllerState(
          vendorID: device.vendorID,
          productID: device.productID,
          runtimeIdentifier: device.runtimeIdentifier
        )
      else { return nil }
      guard output else { return Sample(input: input, output: nil) }
      let sent = try await client.virtualOutputState(
        vendorID: device.vendorID,
        productID: device.productID,
        runtimeIdentifier: device.runtimeIdentifier
      )
      return Sample(input: input, output: sent)
    }
  }

  private func emit(_ event: Event, device: ApplicationServiceDeviceDescription) throws {
    switch (CLIContext.current.format, event.type) {
    case (.json, _): try CLIOutput.jsonLine(event)
    case (.plain, .connected):
      CLIOutput.plain([["connected", event.id, device.identity, device.name]])
    case (.plain, .disconnected): CLIOutput.plain([["disconnected", event.id]])
    case (.plain, .input):
      let input = event.input.map(Self.plainRow) ?? []
      CLIOutput.plain([["input", event.id] + input + (output ? Self.plainRow(event.output) : [])])
    case (.human, .connected):
      CLIOutput.stdout(
        CLILocalized.format(
          "cli.controller.watch.connected",
          "%@ connected: %@ (%@)",
          event.id,
          device.name,
          device.identity
        )
      )
    case (.human, .disconnected):
      CLIOutput.stdout(
        CLILocalized.format("cli.controller.watch.disconnected", "%@ disconnected", event.id)
      )
    case (.human, .input):
      if let input = event.input { CLIOutput.stdout("\(event.id) " + Self.formatted(input)) }
      if output { CLIOutput.stdout("\(event.id) " + Self.formatted(event.output)) }
    }
  }
}
