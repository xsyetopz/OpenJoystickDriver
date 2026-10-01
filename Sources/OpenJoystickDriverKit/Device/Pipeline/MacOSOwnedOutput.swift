/// What OJD still sends to a controller macOS serves natively: only what macOS leaves undone.
/// The protocol family's default covers what its driver does on its own, and the controller
/// record adds its output templates. Every other write is refused.
struct MacOSOwnedOutput: Equatable, Sendable {
  /// Lighting OJD drives because macOS does not.
  let lightingFeatures: Set<PhysicalLightingFeature>
  /// Whether OJD drives the driver's rumble motors because macOS does not.
  let drivesRumble: Bool
  /// The only reports the write executors send, matched by kind, report ID and length.
  let reports: Set<ControllerTemplateReport>
  /// Whether OJD sets a player indicator after the controller's first input report. The manager
  /// picks the slot per controller, so two controllers of one model never share it.
  let setsStartupPlayerIndicator: Bool
  /// Whether OJD makes the driver's startup feature reads, which macOS does not.
  let readsStartupFeatures: Bool

  static let none = Self(
    lightingFeatures: [],
    drivesRumble: false,
    reports: [],
    setsStartupPlayerIndicator: false,
    readsStartupFeatures: false
  )

  /// The family default with the record's rumble template added.
  static func allowance(for protocolID: PhysicalProtocolID, record: DeviceRuntimeProfile?) -> Self {
    let family = familyDefault(for: protocolID)
    guard let template = record?.rumbleTemplate else { return family }
    return Self(
      lightingFeatures: family.lightingFeatures,
      drivesRumble: true,
      reports: family.reports.union([template.report]),
      setsStartupPlayerIndicator: family.setsStartupPlayerIndicator,
      readsStartupFeatures: family.readsStartupFeatures
    )
  }

  private static func familyDefault(for protocolID: PhysicalProtocolID) -> Self {
    switch protocolID {
    // macOS never writes a DualShock 3 / Sixaxis output report 0x01, which carries both the
    // player LED and the rumble motors, so OJD drives both. A Sixaxis without motors ignores the
    // rumble fields. On USB the controller sends no input and ignores that report until the host
    // reads feature 0xF2, which macOS does not do.
    case .sonySixaxis:
      Self(
        lightingFeatures: [.playerIndicator],
        drivesRumble: true,
        reports: [ControllerTemplateReport(kind: .output, reportID: 0x01, length: 49)],
        setsStartupPlayerIndicator: true,
        readsStartupFeatures: true
      )
    default: .none
    }
  }

  /// The write-executor gate for a controller macOS serves.
  func permits(_ report: PhysicalHIDOutputReport, kind: PhysicalHIDReportKind) -> Bool {
    reports.contains(
      ControllerTemplateReport(kind: kind, reportID: report.reportID, length: report.bytes.count)
    )
  }

  /// The driver's output capabilities narrowed to this allowance.
  func narrowing(
    _ capabilities: PhysicalControllerOutputCapabilities
  ) -> PhysicalControllerOutputCapabilities {
    PhysicalControllerOutputCapabilities(
      rumbleMotors: drivesRumble ? capabilities.rumbleMotors : [],
      lightingFeatures: capabilities.lightingFeatures.filter { lightingFeatures.contains($0) },
      binaryRumbleMotors: drivesRumble ? capabilities.binaryRumbleMotors : []
    )
  }
}
