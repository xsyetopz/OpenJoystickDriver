#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The `ojd diagnose` checks as a table: each check with its result, its details and, for a
  /// warning or failure the app can fix, a button for the fix.
  ///
  /// A table row has one line, so the tooltip of a long detail shows it in full.
  struct ActivityDiagnosticsView: View {
    /// Runs the checks and holds their rows.
    @ObservedObject
    var model: ActivityDiagnosticsModel
    /// Why the fix of a check failed, by check id.
    let failures: [String: String]
    /// Runs the fix of a check, given the check's id.
    let perform: (ActivityCheckFix, String) -> Void

    /// The diagnostics content; the checks run once when the view appears.
    var body: some View {
      content.task { await model.runIfNeeded() }
    }

    /// The progress indicator while the checks run, then the table.
    @ViewBuilder
    private var content: some View {
      switch model.state {
      case .idle, .running: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      case .finished(let rows):
        Table(rows) {
          TableColumn(OJDLocalized.string("term.status")) { row in
            Label {
              Text(OJDLocalized.string(row.statusKey))
            } icon: {
              Image(systemName: row.symbolName).foregroundColor(Self.color(of: row.status))
            }
          }.width(min: 90, ideal: 110, max: 140)
          TableColumn(OJDLocalized.string("ui.activity.column.check")) { row in
            Text(row.nameKey.map { OJDLocalized.string($0) } ?? row.id).help(row.id)
          }.width(min: 140, ideal: 200, max: 240)
          TableColumn(OJDLocalized.string("ui.activity.column.details")) { row in
            VStack(alignment: .leading, spacing: OJDSpacing.none) {
              HStack {
                Text(row.detail).lineLimit(1).truncationMode(.tail).textSelection(.enabled)
                  .help(row.detail)
                Spacer(minLength: 8)
                if let fix = row.fix {
                  Button(OJDLocalized.string(fix.titleKey)) { perform(fix, row.id) }
                }
              }
              if let failure = failures[row.id] {
                Text(failure).font(.caption).foregroundColor(Color(NSColor.systemRed))
                  .lineLimit(2).textSelection(.enabled).help(failure)
              }
            }
          }
        }
      }
    }

    /// Returns the color of the result.
    static func color(of status: DiagnoseStatus) -> Color {
      switch status {
      case .pass: return Color(NSColor.systemGreen)
      case .warn: return Color(NSColor.systemOrange)
      case .fail: return Color(NSColor.systemRed)
      case .skip: return Color(NSColor.secondaryLabelColor)
      }
    }
  }

#endif
