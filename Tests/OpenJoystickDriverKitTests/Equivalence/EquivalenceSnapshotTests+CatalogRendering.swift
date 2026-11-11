import Foundation

@testable import OpenJoystickDriverKit

/// Renders a record's behavior as text built only from resolved values and the explicit labels in
/// `EquivalenceSnapshotTests+CatalogLabels.swift`.
extension EquivalenceSnapshotCatalogTests {
  static func write(_ write: PhysicalOutputWrite) -> String {
    switch write {
    case .usb(let packet, let tolerates):
      "usb ep=\(packet.endpoint) timeoutMs=\(packet.timeoutMilliseconds)"
        + " tolerated=\(tolerates) \(hex(packet.bytes))"
    case .hidOutput(let report): "hid-output id=\(report.reportID) \(hex(report.bytes))"
    case .hidFeature(let report): "hid-feature id=\(report.reportID) \(hex(report.bytes))"
    }
  }

  static func writes(_ name: String, _ writes: [PhysicalOutputWrite]) -> [String] {
    writes.isEmpty ? [] : writes.enumerated().map { "\(name)[\($0.offset)] \(write($0.element))" }
  }

  /// The tuning values the record sets, by explicit key label.
  static func tuning(_ tuning: ControllerTuning) -> String {
    let set = ControllerTuning.Key.allCases.compactMap { key in
      tuning.text(of: key).map { "\(label(key))=\($0)" }
    }
    return set.isEmpty ? "-" : set.sorted().joined(separator: ",")
  }

  private static func field(_ field: ReportBitField) -> String {
    let mask = ((1 << field.bitSize) - 1) << (field.bitOffset % 8)
    return "\(field.bitOffset / 8)&\(unsafe String(format: "%02X", mask))"
  }

  private static func layoutLines(_ layout: ControllerInputLayout) -> [String] {
    var lines = [
      "inputLayout reportID=\(layout.reportID.map(String.init) ?? "-")"
        + " minimumLength=\(layout.minimumLength)"
    ]
    for button in layout.buttons {
      lines.append(
        "inputLayout button \(button.control.rawValue)"
          + " \(button.fields.map(field).joined(separator: "|"))"
      )
    }
    for axis in layout.axes {
      lines.append(
        "inputLayout axis \(axis.control.rawValue) byte=\(axis.field.bitOffset / 8)"
          + " bits=\(axis.field.bitSize) signed=\(axis.field.isSigned)"
          + " range=\(axis.field.minimum)...\(axis.field.maximum)"
          + " inverted=\(axis.isInverted)"
      )
    }
    for source in layout.hat {
      switch source {
      case .eightWay(let hat, let neutralUntilNonzero):
        lines.append(
          "inputLayout hat eight-way \(field(hat)) neutralUntilNonzero=\(neutralUntilNonzero)"
        )
      case .directions(let up, let right, let down, let left):
        lines.append(
          "inputLayout hat directions up=\(field(up)) right=\(field(right))"
            + " down=\(field(down)) left=\(field(left))"
        )
      case .table(let hat, let directions):
        let entries = directions.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.rawValue)" }
        lines.append("inputLayout hat table \(field(hat)) \(entries.joined(separator: ","))")
      }
    }
    for (name, trigger) in [("left", layout.leftTrigger), ("right", layout.rightTrigger)] {
      guard let trigger else { continue }
      lines.append(
        "inputLayout trigger \(name) byte=\(trigger.analog.map { String($0.bitOffset / 8) } ?? "-")"
          + " button=\(trigger.button.map(field) ?? "-")"
      )
    }
    return lines
  }

  private static func driverLines(_ record: ControllerRecord) -> [String] {
    let profile = record.profile
    let variant =
      profile.physicalProtocolVariant
      ?? (profile.physicalProtocolID.variants.contains(.usb) ? .usb : nil)
    guard
      case .success(let driver) = ProtocolDriverRegistry.makeUnobservedDriver(
        protocolID: profile.physicalProtocolID,
        variant: variant,
        record: profile,
        model: record.model,
        transportProfile: profile.transportProfile
      )
    else { return ["driver none"] }
    let controls = ProtocolDriverRegistry().capabilities(
      driver.capabilities,
      record: profile
    )
    let output = driver.outputCapabilities
    let plan = driver.sessionPlan
    func milliseconds(_ nanoseconds: UInt64?) -> String {
      nanoseconds.map { String($0 / 1_000_000) } ?? "-"
    }
    var lines = [
      "controls [\(labels(controls.controls))]",
      "output rumble=[\(output.rumbleMotors.map(label).joined(separator: ","))]"
        + " binary=[\(output.binaryRumbleMotors.map(label).joined(separator: ","))]"
        + " lighting=[\(output.lightingFeatures.map(label).joined(separator: ","))]"
        + " adaptiveTriggers=[\(output.adaptiveTriggers.map(label).joined(separator: ","))]",
      "session usbStartupMs=\(milliseconds(plan.usbStartupIntervalNanoseconds))"
        + " usbKeepAliveMs=\(milliseconds(plan.usbKeepAliveIntervalNanoseconds))"
        + " hidStartupMs=\(milliseconds(plan.hidStartupIntervalNanoseconds))"
        + " hidKeepAliveMs=\(milliseconds(plan.hidKeepAliveIntervalNanoseconds))"
        + " minimumHIDOutputMs=\(milliseconds(plan.minimumHIDOutputIntervalNanoseconds))"
        + " recoveryMs=\(milliseconds(plan.hidStartupRecoveryIntervalNanoseconds))"
        + " recoveryRounds=\(plan.hidStartupRecoveryRounds)"
        + " livenessMs=\(milliseconds(plan.inputReportLivenessTimeoutNanoseconds))",
    ]
    // The pipeline sends the description's HID startup writes before the driver's own.
    let declared =
      profile.startupWrites.isEmpty
      ? profile.physicalProtocolID.protocolDescription.startupWrites(
        phase: .startup,
        variant: variant,
        parameters: profile.parameters
      ).map(\.write) : []
    lines += writes("startup", declared + driver.startupWrites())
    lines += writes("activation", driver.activationWrites())
    lines += writes("keepAlive", driver.keepAliveWrites())
    return lines
  }

  /// The runtime behavior a refactor of the record schema must leave unchanged.
  static func profileLines(_ record: ControllerRecord) -> [String] {
    let profile = record.profile
    let transport = profile.transportProfile
    var lines = [
      "protocol=\(label(profile.physicalProtocolID))"
        + " variant=\(label(profile.physicalProtocolVariant))"
        + " ownership=\(label(profile.server))",
      "transport in=\(transport.inputEndpoint) out=\(transport.outputEndpoint)"
        + " interface=\(transport.interfaceNumber) alt=\(transport.alternateSetting)"
        + " interfaceOverride=\(transport.hasInterfaceOverride)"
        + " endpointOverride=\(transport.hasEndpointOverride)"
        + " setConfiguration=\(transport.needsSetConfiguration)"
        + " settleNs=\(transport.postHandshakeSettleNanoseconds)",
      "tuning \(tuning(profile.tuning))",
    ]
    lines += driverLines(record)
    if profile.physicalProtocolID == .xboxGIP {
      // A record that names no packets runs the description's, whose session byte is zero here.
      let packets =
        profile.gipStartupPackets.isEmpty
        ? profile.physicalProtocolID.usbStartupWrites(
          recordWrites: profile.usbStartupWrites,
          variant: profile.physicalProtocolVariant,
          parameters: profile.parameters
        ).map { hex($0.bytes) }
        : profile.gipStartupPackets.map {
          hex(PhysicalProtocolID.xboxGIP.namedPacketWrite($0)?.bytes ?? [])
        }
      lines.append(
        "gip keepAlive=\(label(profile.gipKeepAlivePolicy))"
          + " startup=[\(packets.joined(separator: ","))]"
      )
    }
    for (index, write) in profile.startupWrites.enumerated() {
      lines.append(
        "recordStartup[\(index)] \(label(write.report.kind)) id=\(write.report.reportID)"
          + " length=\(write.report.length) delayMs=\(write.delayMilliseconds ?? 0)"
          + " transport=\(label(write.transport)) \(hex(write.bytes))"
      )
    }
    if let template = profile.rumbleTemplate {
      lines.append(rumbleTemplateLine(template))
    }
    if let layouts = profile.inputLayouts {
      for layout in layouts.layouts { lines += layoutLines(layout) }
    }
    if let uuid = profile.bluetoothLEVibrationCharacteristic {
      lines.append("bluetoothLEVibrationCharacteristic \(uuid)")
    }
    // Parameters that only steer report decoding have no resolved value to print here; the
    // parsed frames snapshot covers their effect for the records with sample reports.
    let parameterEntries = profile.parameters.entries + usageLayoutEntries(profile)
    lines.append("parameters=\(parameterEntries.joined(separator: ","))")
    return lines
  }

  /// The records whose HID usage map the snapshot renders as `usageLayout=<name>`.
  ///
  /// Each name is a record that declares the layout; `usageLayoutEntries` renders the first one
  /// whose map equals the profile's.
  private static let legacyUsageLayouts: [(name: String, vendorID: UInt16, productID: UInt16)] = [
    ("Wr007", 0x11C1, 0x5600), ("ScufEnvision", 0x2E95, 0x434D),
    ("ZRzBrakeLeft", 0x2DC8, 0x301B), ("DragonRise", 0x0079, 0x0006),
  ]

  private static func usageLayoutEntries(_ profile: DeviceRuntimeProfile) -> [String] {
    guard let map = profile.hidUsageMap else { return [] }
    for layout in legacyUsageLayouts {
      let model = ControllerModelID(vendorID: layout.vendorID, productID: layout.productID)
      if ProtocolDriverRegistry().record(for: model)?.hidUsageMap == map {
        return ["usageLayout=\(layout.name)"]
      }
    }
    return ["usageLayout=unknown"]
  }

  /// A rumble template: its target, the motor fields, and the bytes, counter and resend
  /// interval it names beyond a zeroed report.
  static func rumbleTemplateLine(_ template: RumbleOutputTemplate) -> String {
    let motors = template.motors.map { motor, field in
      let encoding = field.encoding == .uInt8 ? "" : ":\(field.encoding.rawValue)"
      return "\(label(motor))@\(field.byte)\(encoding)"
    }.sorted()
    var line =
      switch template.target {
      case .hid(let report):
        "rumbleTemplate \(label(report.kind)) id=\(report.reportID) length=\(report.length)"
      case .usb(let length): "rumbleTemplate usb length=\(length)"
      }
    line += " motors=\(motors.joined(separator: ","))"
    let blank = RumbleOutputTemplate.zeroedBytes(for: template.target)
    if template.bytes != blank { line += " bytes=\(hex(template.bytes))" }
    if let counter = template.counterByte { line += " counter@\(counter)" }
    if let interval = template.resendIntervalMilliseconds { line += " resendMs=\(interval)" }
    return line
  }
}
