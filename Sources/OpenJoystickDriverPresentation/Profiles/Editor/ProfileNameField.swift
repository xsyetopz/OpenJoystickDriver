#if canImport(SwiftUI)

  import AppKit
  import SwiftUI

  /// The profile name field of the create, duplicate and convert sheets, with the message about
  /// a name another profile has or one that is empty once trimmed.
  struct ProfileNameField: View {
    /// The name in the field.
    let text: Binding<String>
    /// Whether another profile has the name.
    let isTaken: Bool

    /// The field, and the message below it when the name is not acceptable.
    var body: some View {
      TextField(OJDLocalized.string("term.profileName"), text: text)
        .ojdAccessibilityLabel(OJDLocalized.string("term.profileName"))
        .help(OJDLocalized.string("ui.profiles.nameHelp"))
      if let message = ProfileNameValidation.problem(of: text.wrappedValue, isTaken: isTaken) {
        Text(message).foregroundColor(Color(NSColor.systemRed)).fixedSize(
          horizontal: false,
          vertical: true
        )
      }
    }
  }

#endif
