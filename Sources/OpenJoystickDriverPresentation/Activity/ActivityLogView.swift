#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
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

    /// The line's text; a warning is orange with a triangle and an error red with an octagon.
    @ViewBuilder
    private func messageText(_ row: ActivityLogEntry) -> some View {
      let text = Text(row.text).font(.system(.body, design: .monospaced)).textSelection(.enabled)
      let severity = row.severity
      if let tone = severity.tone, let symbolName = severity.symbolName {
        HStack(alignment: .firstTextBaseline, spacing: OJDSpacing.small) {
          Image(systemName: symbolName).accessibilityHidden(true)
          text
        }.foregroundStyle(Color(tone.color)).accessibilityElement(children: .combine)
          .ojdAccessibilityLabel(OJDLocalized.string("ui.console.errors") + ": " + row.text)
      } else {
        text
      }
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
          TableColumn(OJDLocalized.string("ui.activity.column.message")) { row in
            messageText(row)
          }
        }
      }
    }
  }

#endif
