#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI
  struct ApplicationSettingsView: View {
    @ObservedObject
    var preferences: SettingsPreferencesModel
    @StateObject
    var commandLineTool = CommandLineToolModel()

    init(preferences: SettingsPreferencesModel = SettingsPreferencesModel()) {
      self.preferences = preferences
    }
  }

#endif
