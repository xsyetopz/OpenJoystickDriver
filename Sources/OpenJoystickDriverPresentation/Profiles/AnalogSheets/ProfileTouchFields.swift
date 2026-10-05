#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileTouchFields: View {
    @Binding
    var draft: ProfileTouchDraft

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

    private func field(_ key: String, _ value: Binding<String>) -> some View {
      VStack(alignment: .leading, spacing: 4) {
        Text(label(key))
        TextField(label(key), text: value).textFieldStyle(RoundedBorderTextFieldStyle())
      }
    }

    private func label(_ key: String) -> String {
      OJDLocalized.string("profiles.touch." + key)
    }
  }
#endif
