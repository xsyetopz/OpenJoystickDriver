/// What OJD still sends to a controller macOS serves natively: only what macOS leaves undone for
/// that family. Every other native controller gets nothing.
struct NativeGamepadWrites: Equatable, Sendable {
  /// Lighting OJD drives because macOS does not.
  let lightingFeatures: Set<PhysicalLightingFeature>
  /// Whether OJD drives the driver's rumble motors because macOS does not.
  let drivesRumble: Bool
  /// HID output report IDs that carry that lighting; the write executors refuse every other
  /// output report and every feature report.
  let outputReportIDs: Set<UInt8>
  /// Whether OJD sets a player indicator after the controller's first input report. The manager
  /// picks the slot per controller, so two controllers of one model never share it.
  let setsStartupPlayerIndicator: Bool
  /// Whether OJD makes the driver's startup feature reads, which macOS does not.
  let readsStartupFeatures: Bool

  static let none = Self(
    lightingFeatures: [],
    drivesRumble: false,
    outputReportIDs: [],
    setsStartupPlayerIndicator: false,
    readsStartupFeatures: false
  )

  /// The allowance table, keyed by bound protocol.
  static func allowance(for protocolID: PhysicalProtocolID) -> Self {
    switch protocolID {
    // macOS never writes a DualShock 3 / Sixaxis output report 0x01, which carries both the
    // player LED and the rumble motors, so OJD drives both. A Sixaxis without motors ignores the
    // rumble fields. On USB the controller sends no input and ignores that report until the host
    // reads feature 0xF2, which macOS does not do.
    case .sonySixaxis:
      Self(
        lightingFeatures: [.playerIndicator],
        drivesRumble: true,
        outputReportIDs: [0x01],
        setsStartupPlayerIndicator: true,
        readsStartupFeatures: true
      )
    default: .none
    }
  }

  /// The write-executor gate for a native controller.
  func permits(_ report: PhysicalHIDOutputReport, kind: PhysicalHIDReportKind) -> Bool {
    kind == .output && outputReportIDs.contains(report.reportID)
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
