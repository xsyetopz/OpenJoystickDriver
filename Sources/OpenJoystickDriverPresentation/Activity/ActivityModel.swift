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

/// An action of the Activity area that did not happen: the alert's title and, when there is more
/// to say, its message.
struct ActivityActionFailure: Equatable {
  /// The alert's title.
  let title: String
  /// The alert's message, or nil when the title says it all.
  let message: String?
}

#if canImport(AppKit) && canImport(SwiftUI)

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
    /// The alert shows in both views.
    @Published
    var failure: ActivityActionFailure?
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

    /// Does the action of a fix button and shows an alert when it fails.
    func perform(_ fix: ActivityCheckFix) {
      if let title = performFix(fix) { failure = ActivityActionFailure(title: title, message: nil) }
    }
  }

  /// The Activity area: the log table or the diagnostic checks, filling the detail column.
  struct ActivityView: View {
    /// The state of the Activity area.
    @ObservedObject
    var model: ActivityModel

    /// The Activity content with the alert for the model's failure.
    var body: some View {
      content.alert(
        isPresented: Binding(
          get: { model.failure != nil },
          set: { if !$0 { model.failure = nil } }
        )
      ) {
        Alert(
          title: Text(model.failure?.title ?? ""),
          message: model.failure?.message.map { Text($0) },
          dismissButton: .default(Text(OJDLocalized.string("action.ok")))
        )
      }
    }

    /// The log table or the diagnostic checks, as the mode says.
    @ViewBuilder
    private var content: some View {
      switch model.mode {
      case .log: ActivityLogView(model: model.log)
      case .diagnostics: ActivityDiagnosticsView(model: model.diagnostics, perform: model.perform)
      }
    }
  }

#endif
