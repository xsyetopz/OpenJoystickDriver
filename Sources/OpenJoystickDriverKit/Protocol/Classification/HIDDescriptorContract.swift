import Foundation

/// The semantic report-descriptor contract `HIDDescriptor` requires before binding.
///
/// It fails closed: every control the classifier relies on must be described by a
/// standard usage, and anything the parser cannot model rejects the descriptor.
/// Vendor-page fields are ignored, so a device whose controls are vendor-only fails.
public enum HIDDescriptorContract {
  /// The rule a HID descriptor violates.
  public enum Violation: String, Equatable, Sendable {
    /// The interface reports no descriptor.
    case missingDescriptor = "missing-descriptor"
    /// The descriptor does not parse.
    case malformedDescriptor = "malformed-descriptor"
    /// The descriptor uses an item the parser does not support.
    case unsupportedItem = "unsupported-item"
    /// Input reports mix a zero report ID with numbered ones.
    case mixedReportNumbering = "mixed-report-numbering"
    /// An input field has an invalid size.
    case invalidFieldSize = "invalid-field-size"
    /// The largest input report differs from the length the host reports.
    case reportLengthMismatch = "report-length-mismatch"
    /// The same standard usage is declared twice in one report.
    case duplicateUsage = "duplicate-usage"
    /// No Joystick, Game Pad or Multi-axis Controller application collection exists.
    case missingControllerCollection = "missing-controller-collection"
    /// No such collection has an absolute X/Y pair or Hat Switch.
    case missingDirectionalInput = "missing-directional-input"
    /// No such collection with a directional input has an absolute non-zero Button usage.
    case missingButtonInput = "missing-button-input"
  }

  /// Returns the first violated rule, or nil when the observed HID facts satisfy
  /// the contract.
  ///
  /// The descriptor must place an absolute directional input (an X/Y pair or a Hat
  /// Switch) and an absolute non-zero Button usage inside the same Generic Desktop
  /// Joystick, Game Pad, or Multi-axis Controller application collection. When the
  /// host reports a maximum input report length, the descriptor's largest input
  /// report, counting its report ID byte, must equal it.
  public static func violation(in layout: HIDLayoutSummary?) -> Violation? {
    guard let descriptor = layout?.reportDescriptor else { return .missingDescriptor }
    guard let parsed = HIDReportDescriptorParser.parse(descriptor: Array(descriptor)) else {
      return .malformedDescriptor
    }
    if parsed.containsUnsupportedItem { return .unsupportedItem }
    if parsed.inputReportIDs.contains(0), parsed.inputReportIDs.count > 1 {
      return .mixedReportNumbering
    }
    if parsed.containsInvalidInputSize { return .invalidFieldSize }
    if let observed = layout?.reports?.first(where: { $0.kind == .input })?.maximumLengthBytes {
      let lengths = parsed.inputReportIDs.map {
        (parsed.payloadSizeBytesByReportID[$0] ?? 0) + ($0 == 0 ? 0 : 1)
      }
      guard (lengths.max() ?? 0) == Int(observed) else { return .reportLengthMismatch }
    }
    // Controls beyond an item's explicit usage list have no field, so a repeat here
    // is the same usage declared twice for distinct controls.
    var usagesByReport: [UInt8: Set<HIDUsage>] = [:]
    for field in parsed.fields where isStandardUsage(field) {
      let usage = HIDUsage(usagePage: field.usagePage, usage: field.usage)
      guard usagesByReport[field.reportID, default: []].insert(usage).inserted else {
        return .duplicateUsage
      }
    }
    let controllers = parsed.applicationCollections.indices.filter {
      parsed.applicationCollections[$0].usagePage == genericDesktopPage
        && controllerCollectionUsages.contains(parsed.applicationCollections[$0].usage)
    }
    guard !controllers.isEmpty else { return .missingControllerCollection }
    var hasDirectionalInput = false
    for collection in controllers {
      let fields = parsed.fields.filter {
        $0.applicationCollection == collection && !$0.flags.isRelative
      }
      let desktopUsages = Set(fields.filter { $0.usagePage == genericDesktopPage }.map(\.usage))
      guard desktopUsages.isSuperset(of: stickUsages) || desktopUsages.contains(hatUsage) else {
        continue
      }
      hasDirectionalInput = true
      let buttonArrays = parsed.arrays.filter {
        $0.applicationCollection == collection && !$0.flags.isRelative
      }
      if fields.contains(where: isButton)
        || buttonArrays.contains(where: { $0.usages.contains(where: isButton) })
      {
        return nil
      }
    }
    return hasDirectionalInput ? .missingButtonInput : .missingDirectionalInput
  }

  /// Whether `field` is a button, or a Generic Desktop axis or hat in the standard set.
  private static func isStandardUsage(_ field: HIDField) -> Bool {
    field.usagePage == buttonPage
      || (field.usagePage == genericDesktopPage && standardAxisUsages.contains(field.usage))
  }

  /// Button usage 0 means no button pressed; it is not a button.
  private static func isButton(_ field: HIDField) -> Bool {
    isButton(HIDUsage(usagePage: field.usagePage, usage: field.usage))
  }

  /// Whether `usage` is a button other than usage 0.
  private static func isButton(_ usage: HIDUsage) -> Bool {
    usage.usagePage == buttonPage && usage.usage != 0
  }

  /// The HID usage page of Generic Desktop controls.
  private static let genericDesktopPage = 0x01
  /// The HID usage page of buttons.
  private static let buttonPage = 0x09
  /// Joystick, Game Pad, and Multi-axis Controller.
  private static let controllerCollectionUsages: Set<Int> = [0x04, 0x05, 0x08]
  /// A directional input is an X/Y pair or a Hat Switch.
  private static let stickUsages: Set<Int> = [0x30, 0x31]
  /// The Generic Desktop usage of the Hat Switch.
  private static let hatUsage = 0x39
  /// X, Y, Z, Rx, Ry, Rz, and Hat Switch.
  private static let standardAxisUsages: Set<Int> = [0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x39]
}
