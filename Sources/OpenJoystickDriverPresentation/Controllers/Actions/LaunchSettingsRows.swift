#if canImport(SwiftUI) && canImport(AppKit)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The launch settings of the apps: the list, Add App, Edit, Remove and Copy Steam Launch Option.
  struct LaunchSettingsRows: View {
    /// The stored settings.
    @StateObject
    private var model = LaunchSettingsModel()
    /// The entry the editor sheet shows, or nil.
    @State
    private var editing: LaunchSettingsModel.Entry?

    /// The row with the list and its buttons, and the notices under it.
    var body: some View {
      Group {
        OJDLabeledRow(OJDLocalized.string("ui.controllers.launchSettings")) {
          HStack {
            Button(OJDLocalized.string("ui.controllers.launchSettings.add")) { add() }
              .help(OJDLocalized.string("ui.help.launchSettingsAdd"))
            Button(OJDLocalized.string("ui.controllers.launchSettings.copySteam")) {
              model.copySteamLaunchOption()
            }.help(OJDLocalized.string("ui.help.launchSettingsCopySteam"))
          }
        }
        if model.entries.isEmpty {
          Text(OJDLocalized.string("ui.controllers.launchSettings.empty")).font(.caption)
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        ForEach(model.entries) { entry in
          LabeledContent(entry.name) {
            HStack {
              Button(OJDLocalized.string("ui.controllers.launchSettings.edit")) { editing = entry }
                .help(OJDLocalized.string("ui.help.launchSettingsEdit"))
              Button(OJDLocalized.string("action.remove")) {
                model.removeLaunchSetting(key: entry.key)
              }
              .help(OJDLocalized.string("ui.help.launchSettingsRemove"))
            }
          }
        }
        Text(OJDLocalized.string("ui.controllers.launchSettings.steamNote")).font(.caption)
          .foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        if model.copied {
          ControllerNoticeText(
            text: OJDLocalized.string("ui.controllers.launchSettings.copied"),
            isError: false
          )
        }
        if let failure = model.failure { ControllerNoticeText(text: failure, isError: true) }
      }.sheet(item: $editing) { entry in
        LaunchSettingEditor(entry: entry, model: model) { editing = nil }
      }
    }

    /// Asks for an app and opens the editor on its launch setting.
    private func add() {
      ControllerFilePanels.chooseApp { app in
        guard let app, let entry = model.entry(adding: app) else { return }
        editing = entry
      }
    }
  }

  /// The sheet that edits the launch setting of one app.
  struct LaunchSettingEditor: View {
    /// The app and its stored setting.
    let entry: LaunchSettingsModel.Entry
    /// The stored settings, which the sheet saves into.
    @ObservedObject
    var model: LaunchSettingsModel
    /// Closes the sheet.
    let close: () -> Void

    /// Whether the program starts with the SDL GameController backend hints.
    @State
    private var backend: Bool
    /// The environment variables, one `NAME=VALUE` per line.
    @State
    private var environmentText: String
    /// The arguments, one per line.
    @State
    private var argumentsText: String

    /// Creates the editor with the fields of the stored setting.
    init(entry: LaunchSettingsModel.Entry, model: LaunchSettingsModel, close: @escaping () -> Void)
    {
      self.entry = entry
      self.model = model
      self.close = close
      _backend = State(initialValue: entry.setting.sdlGameControllerBackend)
      _environmentText = State(
        initialValue: entry.setting.environment.sorted { $0.key < $1.key }
          .map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
      )
      _argumentsText = State(initialValue: entry.setting.arguments.joined(separator: "\n"))
    }

    /// The fields and the Cancel and Save buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.medium) {
        Text(OJDLocalized.formatted("ui.controllers.launchSettings.editor.title", entry.name))
          .font(.headline)
        Toggle(OJDLocalized.string("ui.controllers.launch.gameControllerBackend"), isOn: $backend)
          .help(OJDLocalized.string("platform.macos.cli.virtual.launch.sdlGamecontrollerBackend"))
        field(
          title: "ui.controllers.launchSettings.environment",
          hint: "ui.controllers.launchSettings.environment.hint",
          help: "ui.help.launchSettingsEnvironment",
          text: $environmentText
        )
        field(
          title: "ui.controllers.launchSettings.arguments",
          hint: "ui.controllers.launchSettings.arguments.hint",
          help: "ui.help.launchSettingsArguments",
          text: $argumentsText
        )
        if let failure = model.failure { ControllerNoticeText(text: failure, isError: true) }
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.cancel")) { close() }
            .keyboardShortcut(.cancelAction).help(OJDLocalized.string("a11y.access.cancel"))
          Button(OJDLocalized.string("action.save")) { save() }
            .keyboardShortcut(.defaultAction).help(OJDLocalized.string("ui.help.confirmChange"))
        }
      }.ojdSheet(.compact)
    }

    /// A labeled multi-line field with a hint under it.
    private func field(
      title: String,
      hint: String,
      help: String,
      text: Binding<String>
    ) -> some View {
      VStack(alignment: .leading, spacing: OJDSpacing.small) {
        Text(OJDLocalized.string(title))
        TextEditor(text: text).font(.body).frame(height: 70)
          .ojdAccessibilityLabel(OJDLocalized.string(title)).help(OJDLocalized.string(help))
        Text(OJDLocalized.string(hint)).font(.caption)
          .foregroundColor(Color(NSColor.secondaryLabelColor))
      }
    }

    /// Stores the fields, and closes the sheet when the settings file accepts them.
    private func save() {
      let lines = { (text: String) in
        text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
      }
      do {
        let pairs = try lines(environmentText).map(LaunchSetting.assignment)
        let setting = LaunchSetting(
          sdlGameControllerBackend: backend,
          environment: Dictionary(pairs.map { ($0.name, $0.value) }) { _, last in last },
          arguments: lines(argumentsText)
        )
        if model.save(setting, for: entry.key) { close() }
      } catch let error as LaunchSettingError {
        model.report(error)
      } catch { model.report(error) }
    }
  }

#endif
