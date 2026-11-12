import Combine
import Foundation

/// The two views of the Activity area; the toolbar's segmented control switches them.
enum ActivityMode: Int, CaseIterable {
  /// The log table.
  case log
  /// The diagnostic checks.
  case diagnostics

  /// The localization key of the segment's title.
  var titleKey: String {
    switch self {
    case .log: return "ui.activity.mode.log"
    case .diagnostics: return "ui.activity.mode.diagnostics"
    }
  }
}

/// Whether the Activity log follows the service logs: only while the main window is visible and
/// shows the log.
enum ActivityLogFollowing {
  /// Returns whether the log follows the service logs: the window is visible, the area is Activity
  /// and the log is shown.
  static func shouldFollow(
    windowVisible: Bool,
    area: MainWindowArea,
    mode: ActivityMode
  ) -> Bool {
    windowVisible && area == .activity && mode == .log
  }
}

/// An action of the Activity area that did not happen: the title and, when there is more to say,
/// the message.
struct ActivityActionFailure: Equatable {
  /// What did not happen.
  let title: String
  /// Why, or nil when the title says it all.
  let message: String?

  /// The title, followed by the message when there is one.
  var text: String { [title, message].compactMap { $0 }.joined(separator: " ") }
}

#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The state of the Activity area: which view it shows, the log and the diagnostic checks.
  @MainActor
  final class ActivityModel: ObservableObject {
    /// The view that the area shows.
    @Published
    var mode = ActivityMode.log
    /// The log table's model.
    let log: ActivityLogModel
    /// The diagnostic checks' model.
    let diagnostics: ActivityDiagnosticsModel
    /// The last action that failed.
    ///
    /// The failure row shows in both views.
    @Published
    var failure: ActivityActionFailure?
    /// Why the fix of a check row failed, by check id; the row shows it under its details.
    @Published
    var fixFailures: [String: String] = [:]
    /// Does the action of a fix button and returns why it could not.
    private let performFix: @MainActor (ActivityCheckFix) -> String?

    /// `performFix` does the action of a fix button and returns why it could not, if it could not.
    init(
      log: ActivityLogModel,
      diagnostics: ActivityDiagnosticsModel,
      performFix: @escaping @MainActor (ActivityCheckFix) -> String?
    ) {
      self.log = log
      self.diagnostics = diagnostics
      self.performFix = performFix
    }

    /// Does the fix of the check `checkID` and keeps why it failed, if it did, for that check row.
    func perform(_ fix: ActivityCheckFix, forCheck checkID: String) {
      fixFailures[checkID] = performFix(fix)
    }
  }

  /// The Activity area: the log table or the diagnostic checks, filling the detail column.
  struct ActivityView: View {
    /// The state of the Activity area.
    @ObservedObject
    var model: ActivityModel

    /// The Activity content under the row of the model's failure, which Dismiss clears.
    var body: some View {
      VStack(spacing: OJDSpacing.none) {
        if let failure = model.failure {
          HStack(alignment: .firstTextBaseline, spacing: OJDSpacing.small) {
            Text(failure.text).foregroundColor(Color(NSColor.systemOrange)).fixedSize(
              horizontal: false,
              vertical: true
            )
            Spacer(minLength: 12)
            Button(OJDLocalized.string("action.dismiss")) { model.failure = nil }
          }.padding(.horizontal, 12).padding(.vertical, 8)
          Divider()
        }
        HiddenChangeNotice(content: .needsAdvanced).padding(.horizontal, OJDSpacing.medium)
        content
      }
    }

    /// The log table or the diagnostic checks, as the mode says.
    @ViewBuilder
    private var content: some View {
      switch model.mode {
      case .log: ActivityLogView(model: model.log).ojdInterfaceRow(ActivityRow.log)
      case .diagnostics:
        ActivityDiagnosticsView(
          model: model.diagnostics,
          failures: model.fixFailures,
          perform: model.perform
        ).ojdInterfaceRow(ActivityRow.diagnostics)
      }
    }
  }

#endif
