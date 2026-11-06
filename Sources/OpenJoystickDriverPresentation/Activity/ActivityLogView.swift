#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import SwiftUI

  /// A full-height table of the service log lines.
  ///
  /// The toolbar holds the filter, the search and the actions.
  struct ActivityLogView: View {
    /// The log's model.
    @ObservedObject
    var model: ActivityLogModel

    /// The log content.
    var body: some View {
      content
    }

    /// The load failure with a retry button, a note for no lines, or the table.
    @ViewBuilder
    private var content: some View {
      if let failure = model.loadFailure {
        ServiceFailureStateView(
          title: OJDLocalized.string("ui.console.loadError"),
          message: failure,
          retry: model.start
        ).padding()
      } else if model.rows.isEmpty {
        Text(OJDLocalized.string("ui.console.empty")).foregroundColor(
          Color(NSColor.secondaryLabelColor)
        ).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Table(model.rows) {
          TableColumn(OJDLocalized.string("ui.console.stream")) { row in
            Text(OJDLocalized.string(row.stream.activityTitleKey))
          }.width(min: 60, ideal: 70, max: 90)
          TableColumn(OJDLocalized.string("ui.activity.column.message")) { row in
            Text(row.text).font(.system(.body, design: .monospaced)).textSelection(.enabled)
          }
        }
      }
    }
  }

#endif
