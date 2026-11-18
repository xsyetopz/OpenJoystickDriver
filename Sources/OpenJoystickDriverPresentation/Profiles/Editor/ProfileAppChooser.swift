#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI
  import UniformTypeIdentifiers

  /// The apps a profile applies to: each with its icon and name, a button that removes it, and a
  /// menu that adds a running or installed app or, with "Other...", one picked in an open panel.
  struct ProfileAppChooser: View {
    /// The bundle identifiers of the profile's apps.
    @Binding
    var appIDs: [String]
    /// The installed apps, read when the chooser appears.
    @State
    private var installed: [ProfileAppChoice] = []

    /// The list of apps and the add menu.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.small) {
        Text(OJDLocalized.string("ui.profiles.apps"))
        ForEach(appIDs, id: \.self) { appID in
          let entry = ProfileAppChoices.entry(for: appID, lookup: lookup)
          HStack {
            Image(nsImage: icon(of: entry)).resizable().frame(width: 20, height: 20)
              .accessibilityHidden(true)
            VStack(alignment: .leading) {
              Text(entry.title)
              if !entry.isInstalled {
                Text(OJDLocalized.string("ui.profiles.appNotInstalled"))
                  .font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
              }
            }
            Spacer()
            Button(OJDLocalized.string("action.remove")) {
              appIDs.removeAll { $0 == appID }
            }.ojdAccessibilityLabel(
              OJDLocalized.formatted("ui.profiles.removeAppNamed", entry.title)
            ).help(OJDLocalized.string("ui.profiles.removeAppHelp"))
          }
        }
        Menu(OJDLocalized.string("ui.profiles.addApp")) {
          let running = Self.runningApps()
          let choices = ProfileAppChoices.merged(
            running: running,
            installed: installed,
            excluding: appIDs
          )
          let runningChoices = choices.filter(\.isRunning)
          let installedChoices = choices.filter { !$0.isRunning }
          if !runningChoices.isEmpty {
            Section(header: Text(OJDLocalized.string("ui.profiles.appsRunning"))) {
              ForEach(runningChoices) { item($0) }
            }
          }
          if !installedChoices.isEmpty {
            Section(header: Text(OJDLocalized.string("ui.library.installed"))) {
              ForEach(installedChoices) { item($0) }
            }
          }
          Button(OJDLocalized.string("ui.profiles.appOther")) { chooseOther() }
            .help(OJDLocalized.string("ui.profiles.appOtherHelp"))
        }.help(OJDLocalized.string("ui.profiles.addAppHelp"))
      }.onAppear {
        installed = ProfileAppChoices.installedApps(in: ProfileAppChoices.applicationFolders)
      }
    }

    /// The menu item that adds `choice`.
    private func item(_ choice: ProfileAppChoice) -> some View {
      Button {
        appIDs.append(choice.bundleID)
      } label: {
        Label {
          Text(choice.name)
        } icon: {
          Image(nsImage: Self.icon(at: choice.url))
        }
      }.help(OJDLocalized.string("platform.macos.ui.profiles.addAppItemHelp"))
    }

    /// The running or installed app with `bundleID`.
    private func lookup(_ bundleID: String) -> ProfileAppChoice? {
      (Self.runningApps() + installed).first { $0.bundleID == bundleID }
        ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).flatMap(
          ProfileAppChoices.choice(forAppAt:)
        )
    }

    /// The icon of the entry's app, or the generic app icon.
    private func icon(of entry: ProfileAppEntry) -> NSImage { Self.icon(at: entry.url) }

    /// The icon of the app bundle at `url`, sized for a row.
    private static func icon(at url: URL?) -> NSImage {
      let image =
        url.map { NSWorkspace.shared.icon(forFile: $0.path) }
        ?? NSWorkspace.shared.icon(for: .applicationBundle)
      image.size = NSSize(width: 20, height: 20)
      return image
    }

    /// The running apps with a window and a bundle identifier.
    private static func runningApps() -> [ProfileAppChoice] {
      NSWorkspace.shared.runningApplications.compactMap { app in
        guard app.activationPolicy == .regular, let id = app.bundleIdentifier,
          let name = app.localizedName
        else { return nil }
        return ProfileAppChoice(bundleID: id, name: name, url: app.bundleURL, isRunning: true)
      }
    }

    /// Asks for an app in an open panel that starts in the Applications folder.
    private func chooseOther() {
      let panel = NSOpenPanel()
      panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
      panel.allowedContentTypes = [.applicationBundle]
      panel.allowsMultipleSelection = false
      panel.message = OJDLocalized.string("ui.profiles.appPanelMessage")
      guard panel.runModal() == .OK, let url = panel.url,
        let choice = ProfileAppChoices.choice(forAppAt: url), !appIDs.contains(choice.bundleID)
      else { return }
      appIDs.append(choice.bundleID)
    }
  }

#endif
