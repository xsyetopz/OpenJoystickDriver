import Foundation
import OpenJoystickDriverKit

extension ControllerWatchCommand {
  /// Prints an `ADDED` line for each controller already connected, then input and connection
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
    let object = event.object
    switch (CLIContext.current.format, event.type) {
    case (.json, _): try CLIOutput.jsonLineWithoutEnvelope(event)
    case (.plain, .added):
      CLIOutput.plain([["connected", event.id, device.identity, device.name]])
    case (.plain, .deleted): CLIOutput.plain([["disconnected", event.id]])
    case (.plain, .modified):
      let input = object.input.map(Self.plainRow) ?? []
      CLIOutput.plain([["input", event.id] + input + (output ? Self.plainRow(object.output) : [])])
    case (.human, .added):
      CLIOutput.stdout(
        CLILocalized.format(
          "cli.controller.watch.connected",
          event.id,
          device.name,
          device.identity
        )
      )
    case (.human, .deleted):
      CLIOutput.stdout(
        CLILocalized.format("cli.controller.watch.disconnected", event.id)
      )
    case (.human, .modified):
      if let input = object.input { CLIOutput.stdout("\(event.id) " + Self.formatted(input)) }
      if output { CLIOutput.stdout("\(event.id) " + Self.formatted(object.output)) }
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
