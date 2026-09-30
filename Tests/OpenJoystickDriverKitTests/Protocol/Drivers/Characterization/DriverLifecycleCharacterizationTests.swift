import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

/// Pins what each registry-built protocol driver hands the pipeline today, so replacing the
/// parser lifecycle and output protocols cannot change bytes or flags silently.
///
/// Rendering rules for later slices, which may change the concern helpers but not the pins:
/// - Every concern builds a fresh driver, so sequence counters start at construction and a pin
///   does not depend on the order in which concerns run.
/// - A driver is built for one bound variant, so each IOHID transport label renders the driver
///   classification binds over that transport; a transport that does not bind renders no lines.
/// - A lifecycle concern the driver does not provide renders the pipeline's fallback (`[]`, `0`,
///   `false`, `nil`), exactly as a provider returning that value would.
/// - An output encoder the driver does not provide renders no line; the pipeline accessor
///   returns nil there.
/// - Conformance is pinned only where the pipeline acts on it: `validates` (three feature-read
///   attempts instead of one), `accepts` (replies reach the driver), recovery `supported`, and
///   `capabilities`.
/// - Inputs are parsed with a fixed receipt time, so no line depends on the host clock.
struct DriverLifecycleCharacterizationTests {
  static let registry = ProtocolDriverRegistry()
  static let transports: [String?] = ["USB", "Bluetooth", "BluetoothLowEnergy", nil]
  static let receivedAt: UInt64 = 1_000_000_000

  struct Subject: Sendable {
    let identifier: DeviceIdentifier
    let host: PhysicalTransport
    let protocolID: PhysicalProtocolID
    let variant: PhysicalProtocolVariantID?
    /// Catalog quirks the subject's record carries.
    var quirks: [ControllerQuirk] = []
    /// Input that exercises deferred output, presence, report observation, and battery state.
    var input: [Data] = []
    /// Input after which output encoders render again; set where outputs are gated on it.
    var readyingInput: [Data] = []

    var transport: String { host == .bluetoothClassic ? "Bluetooth" : "USB" }
  }

  /// Builds the subject's driver the way discovery does: classify, then `makeDriver`.
  func driver(_ subject: Subject) throws -> any PhysicalProtocolDriver {
    try catalogParser(subject.identifier, host: subject.host, registry: Self.registry)
  }

  /// The subject's driver bound over the IOHID `transport` property, or nil when classification
  /// rejects that transport.
  func driver(_ subject: Subject, transport: String?) throws -> (any PhysicalProtocolDriver)? {
    let record = try #require(Self.registry.record(for: subject.identifier))
    let host = HIDDeviceStream.hostTransport(forTransportProperty: transport)
    let device = PhysicalDevice(
      vendorID: subject.identifier.controllerIdentity.vendorID,
      productID: subject.identifier.controllerIdentity.productID,
      interfaces: record.usesRawUSB ? nil : [gamepadHIDInterface(host: host)]
    )
    let backend: DeviceAccessBackend = record.usesRawUSB ? .ioUSBHost : .ioHID
    guard case .bound(let binding) = Self.registry.classify(device, backend: backend) else {
      return nil
    }
    return try Self.registry.makeDriver(
      for: binding,
      identifier: subject.identifier,
      claimed: record.usesRawUSB ? USBTransportResolution(profile: record.transportProfile) : nil
    ).get()
  }

  /// The full pinned transcript for one family and variant.
  func transcript(_ subject: Subject) throws -> [String] {
    var lines = capabilities(try driver(subject))
    lines += usbStartup(try driver(subject))
    lines += usbKeepAlive(try driver(subject))
    lines += usbDeferredOutput(try driver(subject), input: subject.input)
    lines += usbInputConnectionOutput(try driver(subject))
    let boundTransports = try Self.transports.filter { try driver(subject, transport: $0) != nil }
    for transport in boundTransports {
      let bound = { try #require(try driver(subject, transport: transport)) }
      lines += hidStartupOutput(try bound(), transport: transport)
      lines += hidStartupFeatureReads(try bound(), transport: transport)
      lines += hidFeatureReplies(try bound(), subject: subject, transport: transport)
      lines += hidStartupFeatureReports(try bound(), transport: transport)
    }
    lines += hidPresenceFeatureReports(try driver(subject))
    lines += hidShutdownFeatureReports(try driver(subject))
    lines += hidPeriodicOutput(try driver(subject))
    lines += hidStatusRequest(try driver(subject))
    lines += hidStartupRecovery(try driver(subject), transport: subject.transport)
    lines += presence(try driver(subject), input: subject.input)
    lines += liveness(try driver(subject), input: subject.input)
    lines += outputs(try driver(subject), stage: "cold")
    guard !subject.readyingInput.isEmpty else { return lines }
    let ready = try driver(subject)
    feed(ready, subject.readyingInput)
    lines += outputs(ready, stage: "ready")
    let reset = try driver(subject)
    feed(reset, subject.readyingInput)
    reset.resetProtocolState()
    lines += outputs(reset, stage: "reset")
    return lines
  }

  /// Parses each report in order and returns the last input event.
  @discardableResult
  func feed(_ driver: any PhysicalProtocolDriver, _ input: [Data]) -> ControllerEvent? {
    var last: ControllerEvent?
    for data in input {
      let event = try? driver.parse(
        report: data,
        receivedAt: MonotonicTimestamp(nanoseconds: Self.receivedAt)
      )
      if let event { last = event }
    }
    return last
  }

  // MARK: - Lifecycle concerns

  func capabilities(_ driver: any PhysicalProtocolDriver) -> [String] {
    let caps = driver.outputCapabilities
    return [
      "capabilities rumble=\(names(caps.rumbleMotors)) binary=\(names(caps.binaryRumbleMotors))",
      "capabilities lighting=\(names(caps.lightingFeatures))",
      "capabilities triggers=\(names(caps.adaptiveTriggers))",
    ]
  }

  func usbStartup(_ driver: any PhysicalProtocolDriver) -> [String] {
    let packets = driver.startupWrites().usbBytes
    let interval = driver.sessionPlan.usbStartupIntervalNanoseconds
    let retries = driver.sessionPlan.usbStartupRetryDelays
    // The pipeline appends the manager-assigned player-slot write after these packets, or on
    // connect when output waits for it; the slot's own encoding is pinned by the `usbPlayer` lines.
    let plan = driver.sessionPlan
    let slot =
      plan.assignsStartupPlayerIndicator && !plan.requiresInputConnectionBeforeOutput
      ? ["usb.startup playerSlot"] : []
    return ["usb.startup interval=\(interval) retries=\(retries) packets=\(packets.count)"]
      + packets.flatMap(render) + slot
  }

  func usbKeepAlive(_ driver: any PhysicalProtocolDriver) -> [String] {
    let packets = driver.keepAliveWrites().usbPackets
    guard let interval = driver.sessionPlan.usbKeepAliveIntervalNanoseconds, !packets.isEmpty else {
      return ["usb.keepAlive nil"]
    }
    return ["usb.keepAlive interval=\(interval)"] + packets.flatMap(render)
  }

  func usbDeferredOutput(_ driver: any PhysicalProtocolDriver, input: [Data]) -> [String] {
    feed(driver, input)
    let packets = driver.drainPendingWrites().usbBytes
    let drained = driver.drainPendingWrites()
    return ["usb.deferred inputs=\(input.count) packets=\(packets.count)"] + packets.flatMap(render)
      + ["usb.deferred drained=\(drained.count)"]
  }

  func usbInputConnectionOutput(_ driver: any PhysicalProtocolDriver) -> [String] {
    [ControllerInputConnectionState.connected, .disconnected].flatMap { state in
      let packets = driver.inputConnectionWrites(for: state).usbBytes
      let plan = driver.sessionPlan
      let slot =
        state == .connected && plan.assignsStartupPlayerIndicator
          && plan.requiresInputConnectionBeforeOutput ? ["usb.connection playerSlot"] : []
      return ["usb.connection[\(state)] packets=\(packets.count)"] + packets.flatMap(render) + slot
    }
  }

  func hidStartupOutput(_ driver: any PhysicalProtocolDriver, transport: String?) -> [String] {
    let reports = driver.startupWrites().hidOutputs
    let plan = driver.sessionPlan
    return [
      "hid.startupOutput[\(label(transport))] interval=\(plan.hidStartupIntervalNanoseconds)"
        + " required=\(plan.requiresStartupOutput) beforeReads=\(plan.outputPrecedesFeatureReads)"
        + " reports=\(reports.count)"
    ] + reports.flatMap(render)
  }

  func hidStartupFeatureReads(_ driver: any PhysicalProtocolDriver, transport: String?) -> [String]
  {
    let requests = driver.startupFeatureReads()
    let validates = driver.sessionPlan.validatesFeatureReplies
    let rendered = requests.map { "\(hexByte($0.reportID))/\($0.length)" }
    return ["hid.featureReads[\(label(transport))] validates=\(validates) requests=\(rendered)"]
  }

  /// Offers every startup read request a well-formed factory reply and a truncated one.
  func hidFeatureReplies(
    _ driver: any PhysicalProtocolDriver,
    subject: Subject,
    transport: String?
  ) -> [String] {
    guard driver.sessionPlan.validatesFeatureReplies else {
      return ["hid.featureReplies[\(label(transport))] accepts=false"]
    }
    return ["hid.featureReplies[\(label(transport))] accepts=true"]
      + driver.startupFeatureReads().map { request in
        let valid = sonyFactoryReply(
          for: request,
          groupedEndpoints: subject.protocolID == .sonyDualShock4 && request.length == 41
        )
        let validAccepted = driver.consumeFeatureReply(valid, request: request)
        let invalidAccepted = driver.consumeFeatureReply(valid.dropLast(), request: request)
        return "  \(hexByte(request.reportID)) valid=\(validAccepted) invalid=\(invalidAccepted)"
      }
  }

  func hidStartupFeatureReports(
    _ driver: any PhysicalProtocolDriver,
    transport: String?
  ) -> [String] {
    let reports = driver.activationWrites().hidFeatures
    return ["hid.featureReports[\(label(transport))] reports=\(reports.count)"]
      + reports.flatMap(render)
  }

  /// The presence-connected path sends the connection writes.
  func hidPresenceFeatureReports(_ driver: any PhysicalProtocolDriver) -> [String] {
    let reports = driver.inputConnectionWrites(for: .connected).hidFeatures
    return ["hid.featureReports[presence] reports=\(reports.count)"] + reports.flatMap(render)
  }

  func hidShutdownFeatureReports(_ driver: any PhysicalProtocolDriver) -> [String] {
    let reports = driver.deactivationWrites().hidFeatures
    return ["hid.shutdownFeatureReports reports=\(reports.count)"] + reports.flatMap(render)
  }

  func hidPeriodicOutput(_ driver: any PhysicalProtocolDriver) -> [String] {
    guard let interval = driver.sessionPlan.hidKeepAliveIntervalNanoseconds else {
      return ["hid.periodic nil"]
    }
    let reports = driver.keepAliveWrites().hidOutputs
    return ["hid.periodic interval=\(interval) reports=\(reports.count)"] + reports.flatMap(render)
  }

  func hidStatusRequest(_ driver: any PhysicalProtocolDriver) -> [String] {
    guard let write = driver.presenceRequestWrite() else { return ["hid.statusRequest nil"] }
    return ["hid.statusRequest"] + [write].hidFeatures.flatMap(render)
  }

  /// Recovery after the subject's own startup output, then after the startup window expires.
  func hidStartupRecovery(_ driver: any PhysicalProtocolDriver, transport: String) -> [String] {
    let beforeStartup = driver.startupRecoveryWrites().hidOutputs
    _ = driver.startupWrites()
    let afterStartup = driver.startupRecoveryWrites().hidOutputs
    driver.expireStartupRecovery()
    let afterExpiry = driver.startupRecoveryWrites()
    return [
      "hid.recovery[\(transport)] supported=\(driver.sessionPlan.hasStartupRecovery)"
        + " beforeStartup=\(beforeStartup.count) afterStartup=\(afterStartup.count)"
    ] + afterStartup.flatMap(render) + ["hid.recovery afterExpiry=\(afterExpiry.count)"]
  }

  func presence(_ driver: any PhysicalProtocolDriver, input: [Data]) -> [String] {
    var lines = [
      "presence requiresConnection=\(driver.sessionPlan.requiresInputConnectionBeforeOutput)"
    ]
    for (index, data) in input.enumerated() {
      _ = try? driver.parse(
        report: data,
        receivedAt: MonotonicTimestamp(nanoseconds: Self.receivedAt)
      )
      let change = driver.consumeInputConnectionStateChange()
      lines.append("presence input#\(index) change=\(change.map { "\($0)" } ?? "nil")")
    }
    return lines
  }

  func liveness(_ driver: any PhysicalProtocolDriver, input: [Data]) -> [String] {
    let timeout = driver.sessionPlan.inputReportLivenessTimeoutNanoseconds
    // Freshness is a liveness signal, so only a driver with a liveness timeout renders it.
    let freshness = timeout == nil ? nil : feed(driver, input)?.isFresh
    if timeout == nil { feed(driver, input) }
    let format = driver.latestInputReportFormat
    let battery = driver.power
    return [
      "liveness timeout=\(timeout.map(String.init) ?? "nil")",
      "liveness observation=" + (freshness.map { "fresh=\($0)" } ?? "nil"),
      "liveness format=\(format ?? "nil")", "battery=" + (battery.map(render) ?? "nil"),
    ]
  }

  func render(_ power: ControllerConnectionState.Power) -> String {
    let range = power.battery.percentage
    let battery =
      range.map { $0.count == 1 ? "\($0.lowerBound)%" : "\($0.lowerBound)-\($0.upperBound)%" }
      ?? "unknown"
    let wired = power.wiredPower.map { $0 ? "yes" : "no" } ?? "unknown"
    return "\(battery) \(power.charging.rawValue) wired-power=\(wired)"
  }

  // MARK: - Rendering

  func label(_ transport: String?) -> String {
    transport == "BluetoothLowEnergy" ? "BLE" : transport ?? "nil"
  }

  func names<Value: RawRepresentable>(_ values: [Value]) -> String where Value.RawValue == String {
    "[" + values.map(\.rawValue).joined(separator: ",") + "]"
  }

  func hexByte(_ byte: UInt8) -> String { "0x" + String(format: "%02x", byte) }

  /// Bytes as 32-byte hex rows, so each pinned line stays short.
  func hexRows(_ bytes: [UInt8]) -> [String] {
    stride(from: 0, to: bytes.count, by: 32).map { start in
      "    "
        + bytes[start..<min(start + 32, bytes.count)].map { String(format: "%02x", $0) }.joined()
    }
  }

  func render(_ bytes: [UInt8]) -> [String] { ["  n=\(bytes.count)"] + hexRows(bytes) }

  func render(_ report: PhysicalHIDOutputReport) -> [String] {
    ["  id=\(hexByte(report.reportID)) n=\(report.bytes.count)"] + hexRows(report.bytes)
  }

  func render(_ packet: PhysicalUSBOutputPacket) -> [String] {
    [
      "  ep=\(hexByte(packet.endpoint)) timeout=\(packet.timeoutMilliseconds)"
        + " n=\(packet.bytes.count)"
    ] + hexRows(packet.bytes)
  }

  func render(_ plan: PhysicalOutputPlan) -> [String] {
    ["  plan interval=\(plan.intervalNanoseconds) reports=\(plan.writes.count)"]
      + plan.writes.flatMap(render)
  }
}
