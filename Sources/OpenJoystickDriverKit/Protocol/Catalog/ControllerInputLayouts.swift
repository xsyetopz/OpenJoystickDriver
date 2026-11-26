/// A controller record's fixed input-report layouts, for a pad whose reports no protocol driver
/// decodes and whose HID descriptor does not describe them. ``ReportLayoutDriver`` reads them.
///
/// Each report is decoded by the one layout that selects it. A report that no layout selects is
/// ignored. A layout changes only the controls it names; every other control keeps its last value.
public struct ControllerInputLayouts: Equatable, Sendable {
  /// The layouts, in the order the record lists them.
  public let layouts: [ControllerInputLayout]

  /// Fails unless there is at least one layout and no two layouts select the same report.
  init(layouts: [ControllerInputLayout]) throws(ControllerRecordProblem) {
    guard !layouts.isEmpty else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.inputLayout.layoutsEmpty",
        "input lists at least one layout"
      )
    }
    for (index, layout) in layouts.enumerated() {
      for other in layouts[(index + 1)...] where layout.selectsSameReport(as: other) {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.inputLayout.layoutsSameReport",
          arguments: [layout.selectorDescription, other.selectorDescription],
          "two input layouts select the same report: \(layout.selectorDescription) and "
            + other.selectorDescription
        )
      }
    }
    self.layouts = layouts
  }

  /// Every control any layout decodes.
  var controls: Set<Control> { layouts.reduce(into: []) { $0.formUnion($1.controls) } }

  /// The index of the layout that selects `bytes`; nil when none does.
  func indexOfLayout(selecting bytes: [UInt8]) -> Int? {
    layouts.firstIndex { $0.selects(bytes) }
  }
}
