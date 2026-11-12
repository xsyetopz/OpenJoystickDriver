#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The Macros section: the macros of the profile, each with an edit and a remove button.
  struct ProfileMacrosSection: View {
    /// The macros of the profile.
    let macros: [RemappingMacro]
    /// Opens a sheet.
    let openSheet: (ProfileEditorSheet) -> Void
    /// Removes the macro with the identifier.
    let removeMacro: (UUID) -> Void

    /// The macros section with an add button.
    var body: some View {
      Section(
        header: HStack {
          Spacer()
          OJDCompactSymbolButton(
            symbolName: "plus",
            label: OJDLocalized.string("ui.profiles.addMacro")
          ) { openSheet(.macro(nil)) }
        }
      ) {
        if macros.isEmpty {
          Text(OJDLocalized.string("ui.profiles.noMacros"))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        ForEach(macros) { macro in
          HStack {
            Text(macro.name)
            Spacer()
            OJDCompactSymbolButton(
              symbolName: "pencil",
              label: OJDLocalized.string("ui.profiles.editMacro")
            ) { openSheet(.macro(macro)) }
            OJDCompactSymbolButton(
              symbolName: "minus.circle",
              label: OJDLocalized.string("action.remove")
            ) { removeMacro(macro.id) }
          }
        }
      }
    }
  }

#endif
