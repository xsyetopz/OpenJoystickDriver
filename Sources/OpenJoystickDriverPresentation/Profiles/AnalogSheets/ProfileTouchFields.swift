#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  /// The fields of one touch surface mapping: the mode and its settings.
  struct ProfileTouchFields: View {
    /// The touch mapping being edited.
    @Binding
    var draft: ProfileTouchDraft

    /// The enabled toggle and, while it is on, the mode and the settings of the touch input.
    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Toggle(label("enabled"), isOn: $draft.enabled)
        if draft.enabled {
          Picker(label("mode"), selection: $draft.mode) {
            Text(label("pointer")).tag(RemappingTouchMode.pointer)
            Text(label("leftStick")).tag(RemappingTouchMode.leftStick)
            Text(label("rightStick")).tag(RemappingTouchMode.rightStick)
          }
          if draft.mode == .pointer {
            field("pointerSensitivity", $draft.pointerSensitivity)
          } else {
            field("stickRadius", $draft.stickRadius)
            field("deadzone", $draft.deadzone)
          }
        }
      }
    }

    /// A labeled text field for the touch setting called `key`.
    private func field(_ key: String, _ value: Binding<String>) -> some View {
      VStack(alignment: .leading, spacing: 4) {
        Text(label(key))
        TextField(label(key), text: value).textFieldStyle(RoundedBorderTextFieldStyle())
      }
    }

    /// Returns the text of the touch field called `key`.
    private func label(_ key: String) -> String {
      OJDLocalized.string("ui.profiles.touch." + key)
    }
  }
#endif
