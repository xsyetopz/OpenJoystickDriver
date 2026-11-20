/// The output that OJD still sends to a controller that macOS serves natively.
///
/// That is only what macOS leaves undone: the protocol family's default covers what its driver does
/// on its own, and the controller record adds its output templates. The write executors refuse
/// every other write.
struct MacOSOwnedOutput: Equatable, Sendable {
  /// Lighting OJD drives because macOS does not.
  let lightingFeatures: Set<PhysicalLightingFeature>
  /// Whether OJD drives the driver's rumble motors because macOS does not.
  let drivesRumble: Bool
  /// The only reports the write executors send, matched by kind, report ID and length.
  let reports: Set<ControllerTemplateReport>
  /// Whether OJD sets a player indicator after the controller's first input report.
  ///
  /// The manager picks the slot per controller, so two controllers of one model never share it.
  let setsStartupPlayerIndicator: Bool
  /// Whether OJD makes the driver's startup feature reads, which macOS does not.
  let readsStartupFeatures: Bool

  /// The allowance that permits no output.
  static let none = Self(
    lightingFeatures: [],
    drivesRumble: false,
    reports: [],
    setsStartupPlayerIndicator: false,
    readsStartupFeatures: false
  )

  /// The family default with the reports of the record's rumble and player-indicator templates
  /// added.
  ///
  /// A player-indicator template also makes OJD set the controller's slot after its first input
  /// report, as the macOS-served Sony families do.
  static func allowance(for protocolID: PhysicalProtocolID, record: DeviceRuntimeProfile?) -> Self {
    let family = protocolID.protocolDescription.macOSOwnedOutput
    let rumble = record?.rumbleTemplate?.report
    let playerIndicator = record?.playerIndicatorTemplate?.report
    guard rumble != nil || playerIndicator != nil else { return family }
    return Self(
      lightingFeatures: playerIndicator == nil
        ? family.lightingFeatures : family.lightingFeatures.union([.playerIndicator]),
      drivesRumble: family.drivesRumble || rumble != nil,
      reports: family.reports.union([rumble, playerIndicator].compactMap { $0 }),
      setsStartupPlayerIndicator: family.setsStartupPlayerIndicator || playerIndicator != nil,
      readsStartupFeatures: family.readsStartupFeatures
    )
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
