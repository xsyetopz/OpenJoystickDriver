#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The command-line tool link, the Xbox USB driver extension, the developer tools switch and,
  /// while it is on, the developer tools.
  struct AdvancedPaneView: View {
    /// The switches of Advanced.
    @ObservedObject
    var preferences: SettingsPreferencesModel
    /// The command-line tool link.
    let commandLineTool: CommandLineToolModel
    /// The developer tools, shown while their switch is on.
    let developerTools: DeveloperToolsViewModel
    /// The driver extension state and actions.
    let runtime: RuntimeViewModel

    /// The Advanced form: the command-line tool, the driver extension and the developer tools
    /// switch.
    var body: some View {
      Form {
        SettingsErrorSection(preferences: preferences)
        CommandLineToolSection(commandLineTool: commandLineTool)
        DriverExtensionSection(runtime: runtime)
        Section(OJDLocalized.string("ui.settings.advanced.developerTools")) {
          SettingsSwitchRow(
            title: OJDLocalized.string("ui.settings.advanced.enableDeveloperTools"),
            description: OJDLocalized.string("ui.settings.advanced.developerToolsDescription"),
            isOn: Binding(
              get: { preferences.developerToolsEnabled },
              set: { preferences.setDeveloperToolsEnabled($0) }
            )
          )
        }
        if preferences.developerToolsEnabled {
          DeveloperToolsView(model: developerTools)
          DeveloperSoakTestSection(model: developerTools.soakTest)
        }
      }.ojdGroupedForm()
    }
  }

#endif
