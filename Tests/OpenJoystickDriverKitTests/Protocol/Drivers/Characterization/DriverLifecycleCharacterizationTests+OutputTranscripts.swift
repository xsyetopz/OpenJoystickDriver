import Foundation
import Testing

@testable import OpenJoystickDriverKit

// Physical output through DeviceManager, recorded by `ScriptedHIDAccessBackend`. Each transcript
// renders only the reports recorded after its startup, and each list's order is pinned as in
// `+StartupSteps.swift`. Raw-USB families need the USB transport and are not covered here.
extension DriverLifecycleCharacterizationTests {
  struct RecordedCounts {
    let outputs: Int
    let features: Int
  }

  func recordedCounts(_ recording: HIDStartupRecording) async -> RecordedCounts {
    RecordedCounts(
      outputs: await recording.backend.recordedOutputReports().count,
      features: await recording.backend.recordedFeatureReports().count
    )
  }

  /// Reports recorded since `counts`.
  func recordedSteps(
    _ recording: HIDStartupRecording,
    since counts: RecordedCounts
  ) async -> [String] {
    let outputs = await recording.backend.recordedOutputReports().dropFirst(counts.outputs)
    let features = await recording.backend.recordedFeatureReports().dropFirst(counts.features)
    return ["outputs=\(outputs.count)"] + outputs.flatMap(render) + ["features=\(features.count)"]
      + features.flatMap(render)
  }

  /// Delivers `input` as input reports, each with its first byte as the report ID.
  func deliver(_ input: [Data], to recording: HIDStartupRecording, locationID: UInt32) async {
    for data in input {
      await recording.manager.handleHIDEvent(
        .inputReport(
          locationID: locationID,
          connectionID: recording.connection.connectionID,
          reportID: data.first ?? 0,
          data: data
        )
      )
    }
  }

  /// Starts `subject` over its own transport, delivers its readying input, then suspends it,
  /// which neutralizes every advertised output channel before the session is suspended.
  func neutralizationSteps(_ subject: Subject, locationID: UInt32) async -> [String] {
    let isSteam = subject.protocolID == .valveSteamController
    let recording = await startHIDController(
      subject,
      transport: subject.transport,
      locationID: locationID,
      interface: isSteam ? steamHIDInterface(number: 1) : nil
    )
    await deliver(subject.readyingInput, to: recording, locationID: locationID)
    // Keep-alive writes (GameSir sends one every 500 ms) are wall-clock paced and not part of
    // neutralization; stop them so a slow run cannot interleave one into the transcript.
    for task in await recording.manager.hidPeriodicOutputTasks.values {
      task.cancel()
      await task.value
    }
    let counts = await recordedCounts(recording)
    let identity = subject.identifier.controllerIdentity
    let result = await recording.manager.suspendController(
      vendorID: identity.vendorID,
      productID: identity.productID,
      runtimeIdentifier: nil
    )
    let steps = await recordedSteps(recording, since: counts)
    await recording.manager.stop()
    return ["suspend state=\(result.state) failure=\(result.failure.map { "\($0)" } ?? "nil")"]
      + steps
  }

  /// A never-seized native pad on USB, recorded like a catalog controller.
  func startNativeController(
    _ identifier: DeviceIdentifier,
    locationID: UInt32
  ) async -> HIDStartupRecording {
    let backend = ScriptedHIDAccessBackend()
    await backend.enableOutputReports()
    await backend.enableFeatureReports()
    let connection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: identifier.controllerIdentity.vendorID,
        productID: identifier.controllerIdentity.productID,
        productName: "Native controller",
        transportProperty: "USB",
        physicalLocationIdentifier: locationID,
        interfaces: [gamepadHIDInterface(host: .usb)],
        nativePassThrough: true
      ),
      routingLocationID: locationID
    )
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: connection, ownership: .unknown)
    ])
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend)
    )
    await manager.markStartedForTest()
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .unknown))
    return HIDStartupRecording(backend: backend, manager: manager, connection: connection)
  }

  func connectedIdentifier(_ recording: HIDStartupRecording) async throws -> DeviceIdentifier {
    try #require(await recording.manager.pipelines.keys.first)
  }

  func capabilityLine(_ recording: HIDStartupRecording) async -> String {
    let caps = await recording.manager.connectedDeviceDescriptions().first?
      .physicalOutputCapabilities
    guard let caps else { return "capabilities nil" }
    return
      "capabilities rumble=\(names(caps.rumbleMotors)) lighting=\(names(caps.lightingFeatures))"
  }

  /// Native Sixaxis: rumble, a stop-rumble, then teardown, which neutralizes and deactivates.
  func nativeSixaxisOutputSteps() async throws -> [String] {
    let recording = await startNativeController(Self.identifier(0x054C, 0x0268), locationID: 310)
    let identifier = try await connectedIdentifier(recording)
    var lines = [await capabilityLine(recording)]
    var counts = await recordedCounts(recording)
    let rumble = await recording.manager.sendManualRumble(
      for: identifier,
      left: 255,
      right: 255,
      lt: 0,
      rt: 0,
      durationMs: 50
    )
    lines += ["rumble=\(rumble)"] + (await recordedSteps(recording, since: counts))
    counts = await recordedCounts(recording)
    let stop = await recording.manager.sendOutputForTest(.stopRumble, for: identifier)
    lines += ["stop=\(stop)"] + (await recordedSteps(recording, since: counts))
    counts = await recordedCounts(recording)
    await recording.manager.stop()
    return lines + ["teardown"] + (await recordedSteps(recording, since: counts))
  }

  /// Native DualShock 4: every manual and mapping output request, then teardown.
  func nativeDualShock4OutputSteps() async throws -> [String] {
    let recording = await startNativeController(Self.identifier(0x054C, 0x09CC), locationID: 311)
    let identifier = try await connectedIdentifier(recording)
    let manager = recording.manager
    let counts = await recordedCounts(recording)
    let rumble = await manager.sendManualRumble(
      for: identifier,
      left: 255,
      right: 255,
      lt: 0,
      rt: 0,
      durationMs: 50
    )
    let player = await manager.sendOutputForTest(.setPlayerIndicator(.player2), for: identifier)
    let color = await manager.sendOutputForTest(
      .setRGB(ControllerColor(red: 0x11, green: 0x22, blue: 0x33)),
      for: identifier
    )
    let brightness = await manager.sendOutputForTest(
      .setLightBrightness(UnipolarValue(byte: 0x80)),
      for: identifier
    )
    let mapping = await manager.setMappingPhysicalOutput(
      .rumble(motor: .leftMain, intensity: 0.5),
      active: true,
      owner: UUID(),
      for: identifier
    )
    let results = [
      "rumble=\(rumble)", "player=\(player)", "color=\(color)", "brightness=\(brightness)",
      "mapping=\(mapping)",
    ]
    var lines = [await capabilityLine(recording)] + results
    lines += await recordedSteps(recording, since: counts)
    let afterRequests = await recordedCounts(recording)
    await manager.stop()
    return lines + ["teardown"] + (await recordedSteps(recording, since: afterRequests))
  }

  /// DualShock 4 Bluetooth with a mapping rumble claim active, then a manual stop-rumble.
  func stopUnderMappingClaimSteps() async throws -> [String] {
    let recording = await startHIDController(
      Self.dualShock4Bluetooth,
      transport: "Bluetooth",
      locationID: 312
    )
    let identifier = try await connectedIdentifier(recording)
    var counts = await recordedCounts(recording)
    let mapping = await recording.manager.setMappingPhysicalOutput(
      .rumble(motor: .leftMain, intensity: 0.5),
      active: true,
      owner: UUID(),
      for: identifier
    )
    var lines = ["mapping=\(mapping)"] + (await recordedSteps(recording, since: counts))
    counts = await recordedCounts(recording)
    let stop = await recording.manager.sendOutputForTest(.stopRumble, for: identifier)
    lines += ["stop=\(stop)"] + (await recordedSteps(recording, since: counts))
    await recording.manager.stop()
    return lines
  }

  /// DualShock 4 Bluetooth manual rumble with trigger channels set, read before the scheduled
  /// 5000 ms stop; then trigger channels alone.
  func manualTriggerRumbleSteps() async throws -> [String] {
    let recording = await startHIDController(
      Self.dualShock4Bluetooth,
      transport: "Bluetooth",
      locationID: 313
    )
    let identifier = try await connectedIdentifier(recording)
    var lines: [String] = []
    for (left, right) in [(UInt8(0x40), UInt8(0x80)), (0, 0)] {
      let counts = await recordedCounts(recording)
      let sent = await recording.manager.sendManualRumble(
        for: identifier,
        left: left,
        right: right,
        lt: 0x20,
        rt: 0x10,
        durationMs: 5000
      )
      lines += ["rumble main=\(left),\(right) triggers=32,16 sent=\(sent)"]
      lines += await recordedSteps(recording, since: counts)
    }
    await recording.manager.stop()
    return lines
  }

  /// Steam wired manual rumble at 0 ms: arbitration encodes the request at 0 ms, then releases
  /// the manual claim and encodes the all-zero stop.
  func steamArbitrationRumbleSteps() async throws -> [String] {
    let recording = await startHIDController(
      Self.steamWired,
      transport: "USB",
      locationID: 314,
      interface: steamHIDInterface(number: 1)
    )
    let identifier = try await connectedIdentifier(recording)
    let counts = await recordedCounts(recording)
    let sent = await recording.manager.sendManualRumble(
      for: identifier,
      left: 0x40,
      right: 0x80,
      lt: 0,
      rt: 0,
      durationMs: 0
    )
    let steps = await recordedSteps(recording, since: counts)
    await recording.manager.stop()
    return ["rumble ms=0 sent=\(sent)"] + steps
  }
}
