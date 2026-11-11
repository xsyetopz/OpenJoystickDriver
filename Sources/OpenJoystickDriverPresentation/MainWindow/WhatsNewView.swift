#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// Decides whether the main window shows the changes of the installed version, and holds what
  /// the sheet shows.
  @MainActor
  final class WhatsNewModel: ObservableObject {
    /// Whether the main window shows the sheet.
    @Published
    var isPresented = false
    /// The installed version that the sheet names.
    private(set) var version = ""
    /// The changelog section of the installed version.
    private(set) var text = ""

    private let settings: SettingsStore
    private let installed: String
    private let changelog: () -> String?

    /// Creates the model for the `installed` version, with the changelog text from `changelog`.
    init(
      settings: SettingsStore = SettingsStore(),
      installed: String = ApplicationVersion.current,
      changelog: @escaping () -> String? = Changelog.bundled
    ) {
      self.settings = settings
      self.installed = installed
      self.changelog = changelog
    }

    /// Shows the sheet when the changelog has a section for the installed version that was not
    /// shown before, and records the version.
    ///
    /// A settings file that cannot be read or written shows nothing, because the section would
    /// show at every opening otherwise.
    func presentIfNeeded() {
      guard let changelog = changelog(),
        let stored = try? settings.load(),
        let section = Changelog.toShow(installed: installed, lastShown: stored.lastShownChangelogVersion, in: changelog),
        (try? settings.setLastShownChangelogVersion(installed)) != nil
      else { return }
      version = installed
      text = section
      isPresented = true
    }
  }

  /// The sheet with the changes of the installed version.
  struct WhatsNewView: View {
    @ObservedObject
    var model: WhatsNewModel

    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.medium) {
        Text(OJDLocalized.formatted("ui.whatsNew.title", model.version)).font(.headline)
        ScrollView {
          Text(
            (try? AttributedString(
              markdown: model.text,
              options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(model.text)
          ).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minHeight: 200)
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.done")) { model.isPresented = false }
            .keyboardShortcut(.defaultAction)
        }
      }.ojdSheet(.regular)
    }
  }

  /// Presents the What's New sheet over the window that holds it.
  struct WhatsNewSheetHost: View {
    @ObservedObject
    var model: WhatsNewModel

    var body: some View {
      Color.clear.sheet(isPresented: $model.isPresented) { WhatsNewView(model: model) }
    }
  }

#endif
