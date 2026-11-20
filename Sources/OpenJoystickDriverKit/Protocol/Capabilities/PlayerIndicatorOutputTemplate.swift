/// A controller's player-indicator report: one byte of a HID output or feature report whose value
/// lights the LEDs of a player slot, with the rest of the report zero.
///
/// It drives a controller that macOS serves but leaves the player LEDs undone, without code of its
/// own for the report's layout. The record names each slot's byte value, so a mapping that
/// hardware contradicts changes in the record alone.
public struct PlayerIndicatorOutputTemplate: Equatable, Sendable {
  /// Why a template needs a HID mode: a raw-USB packet carries no HID report.
  static let templateKindProblem = ControllerRecordProblem.rule(
    "error.E5007.playerIndicator.templateKind",
    "a player-indicator template is a HID report, so a raw-USB mode cannot name one"
  )
  /// Why a template needs a driver that encodes it.
  static let driverProblem = ControllerRecordProblem.rule(
    "error.E5007.playerIndicator.templateDriver",
    "player-indicator templates require a driver that encodes them"
  )

  /// The HID report the template writes.
  public let report: ControllerTemplateReport
  /// The offset of the byte that carries the slot's value.
  public let byte: Int
  /// The byte value of every slot, off included.
  public let values: [PhysicalPlayerIndicator: UInt8]

  /// Fails unless the report is an output or feature report of 1...64 bytes, `byte` is a writable
  /// byte of it, and `values` names every slot.
  init(
    report: ControllerTemplateReport,
    byte: Int,
    values: [PhysicalPlayerIndicator: UInt8]
  ) throws(ControllerRecordProblem) {
    guard report.kind != .input else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.playerIndicator.reportKind",
        "a player-indicator template writes an output or feature report"
      )
    }
    guard (1...64).contains(report.length) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.playerIndicator.reportLength",
        "a player-indicator report is 1...64 bytes long"
      )
    }
    guard report.writableBytes.contains(byte),
      Set(values.keys) == Set(PhysicalPlayerIndicator.allCases)
    else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.playerIndicator.byte",
        "the player-indicator byte lies after the report ID in the report; every slot has a value"
      )
    }
    self.report = report
    self.byte = byte
    self.values = values
  }

  /// The player indicator the template drives.
  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    PhysicalControllerOutputCapabilities(lightingFeatures: [.playerIndicator])
  }

  /// The report that shows `indicator`.
  func write(_ indicator: PhysicalPlayerIndicator) -> PhysicalOutputWrite {
    var bytes = RumbleOutputTemplate.zeroedBytes(for: .hid(report))
    bytes[byte] = values[indicator] ?? 0
    return report.write(bytes)
  }

  /// The write of a player-indicator command; any other command is unsupported.
  func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    guard case .setPlayerIndicator(let indicator) = command else {
      throw .unsupportedCapability(command.capability)
    }
    return PhysicalOutputPlan(writes: [write(indicator)])
  }
}

extension PhysicalPlayerIndicator {
  /// The lowerCamelCase key of a record's player-indicator value for this slot.
  var recordKey: String { self == .off ? "off" : "player\(rawValue)" }
}
