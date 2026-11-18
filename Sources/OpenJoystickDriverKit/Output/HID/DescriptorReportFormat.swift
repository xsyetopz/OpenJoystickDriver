import Foundation

/// Builds input reports for a HID report descriptor that the subset parser reads.
///
/// Consumers that pick their behavior by VID/PID, often SDL, also check the descriptor and the
/// report bytes, so a spoofed VID/PID alone is not enough.
public struct HIDDescriptorReportFormat: VirtualGamepadReportFormat, Sendable {
  /// The descriptor bytes.
  public let descriptor: [UInt8]
  /// The payload size of the input report.
  public let inputReportPayloadSize: Int
  /// The ID of the input report; nil when the descriptor has no report IDs.
  public let inputReportID: UInt8?
  /// The payload size of the output report; nil when the descriptor declares none.
  public let outputReportPayloadSize: Int?
  /// The ID of the output report; nil when the descriptor declares none.
  public let outputReportID: UInt8?

  /// Packs a state into the input report of the descriptor.
  private let packer: HIDReportPacker

  /// Why a descriptor cannot back a report format.
  public enum Error: Swift.Error, CustomStringConvertible, Equatable, Sendable {
    /// The descriptor has no input report with buttons, axes or a hat switch.
    case noSuitableInputReport
    /// The descriptor is truncated or its collections are unbalanced.
    case cannotParseDescriptor

    /// The text of the error.
    public var description: String {
      switch self {
      case .noSuitableInputReport:
        return "Descriptor does not contain a usable GamePad-style input report (buttons/axes/hat)."
      case .cannotParseDescriptor: return "Failed to parse HID report descriptor."
      }
    }
  }

  /// Reads `descriptor` and builds the input report from its most gamepad-like report.
  ///
  /// `buttonUsageMap`, `digitalUsageMap` and `axisUsageMap` choose the usage that carries each part
  /// of the state. `outputReportID` and `outputReportPayloadSize` describe the output report that
  /// the descriptor declares, if any.
  ///
  /// - Throws: ``Error/cannotParseDescriptor`` or ``Error/noSuitableInputReport``.
  public init(
    descriptor: [UInt8],
    outputReportID: UInt8? = nil,
    outputReportPayloadSize: Int? = nil,
    buttonUsageMap: [Int: Int] = [:],
    digitalUsageMap: [Int: HIDInputUsage] = [:],
    axisUsageMap: [HIDAxisRole: HIDInputUsage] = HIDAxisRole.standardUsages
  ) throws {
    self.descriptor = descriptor
    guard let parsed = HIDReportDescriptorParser.parse(descriptor: descriptor) else {
      throw Error.cannotParseDescriptor
    }
    guard
      let bestPacker = HIDReportPacker.bestEffortGamepadPacker(
        from: parsed,
        buttonUsageMap: buttonUsageMap,
        digitalUsageMap: digitalUsageMap,
        axisUsageMap: axisUsageMap
      )
    else { throw Error.noSuitableInputReport }
    self.packer = bestPacker
    self.inputReportID = bestPacker.reportID == 0 ? nil : bestPacker.reportID
    self.inputReportPayloadSize = bestPacker.payloadSizeBytes
    self.outputReportID = outputReportID
    self.outputReportPayloadSize = outputReportPayloadSize
  }

  /// The input report of `state`, packed as the descriptor declares.
  public func buildInputReport(from state: VirtualGamepadState) -> [UInt8] {
    packer.pack(state: state)
  }
}
