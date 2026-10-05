import Foundation
import OpenJoystickDriverKit

extension ControllerWatchCommand {
  /// Prints a `connected` line for each controller already connected, then input and connection
  /// changes for every controller until `duration` elapses or the command is interrupted.
  func watchAll() async throws {
    let client = try await ServiceConnection.open()
    defer { client.disconnect() }
    if CLIContext.current.format == .human {
      CLIOutput.success(
        CLILocalized.text(
          "cli.controller.watch.all_started"
        )
      )
    }
    var poller = ControllerWatchPoller(
      source: ServiceWatchSource(client: client, timeout: CLIContext.current.requestTimeout)
    )
    let output = output
    _ = try await pollController(duration: duration) {
      let updates = try await poller.poll(
        now: DispatchTime.now().uptimeNanoseconds,
        includeOutput: output
      )
      for update in updates { try emit(update.event, device: update.device) }
      return false
    }
  }

  private func emit(
    _ event: ControllerWatchEvent,
    device: ApplicationServiceDeviceDescription
  ) throws {
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
          event.id,
          device.name,
          device.identity
        )
      )
    case (.human, .disconnected):
      CLIOutput.stdout(
        CLILocalized.format("cli.controller.watch.disconnected", event.id)
      )
    case (.human, .input):
      if let input = event.input { CLIOutput.stdout("\(event.id) " + Self.formatted(input)) }
      if output { CLIOutput.stdout("\(event.id) " + Self.formatted(event.output)) }
    }
  }
}

/// Reads controllers through the service socket, each read bounded by the request timeout.
private struct ServiceWatchSource: ControllerWatchSource {
  let client: ApplicationServiceClient
  let timeout: Double

  func devices() async throws -> [ApplicationServiceDeviceDescription] {
    try await ServiceConnection.withDeadline(seconds: timeout) {
      try await client.getStatus().connectedDevices
    }
  }

  func state(of device: ApplicationServiceDeviceDescription) async throws -> ControllerState? {
    try await ServiceConnection.withDeadline(seconds: timeout) {
      try await client.controllerState(
        vendorID: device.vendorID,
        productID: device.productID,
        runtimeIdentifier: device.runtimeIdentifier
      )
    }
  }

  func output(
    of device: ApplicationServiceDeviceDescription
  ) async throws
    -> ApplicationServiceVirtualOutputState?
  {
    try await ServiceConnection.withDeadline(seconds: timeout) {
      try await client.virtualOutputState(
        vendorID: device.vendorID,
        productID: device.productID,
        runtimeIdentifier: device.runtimeIdentifier
      )
    }
  }
}
