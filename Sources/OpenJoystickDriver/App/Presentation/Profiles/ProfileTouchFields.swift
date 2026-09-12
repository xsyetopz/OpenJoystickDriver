#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileTouchFields: View {
    @Binding var draft: ProfileTouchDraft

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Toggle(label("enabled", "Enable continuous touch output"), isOn: $draft.enabled)
        if draft.enabled {
          Picker(label("mode", "Touch mode"), selection: $draft.mode) {
            Text(label("pointer", "Pointer")).tag(RemappingTouchMode.pointer)
            Text(label("leftStick", "Left stick")).tag(RemappingTouchMode.leftStick)
            Text(label("rightStick", "Right stick")).tag(RemappingTouchMode.rightStick)
          }
          if draft.mode == .pointer {
            field("pointerSensitivity", "Pointer points per surface", $draft.pointerSensitivity)
          } else {
            field("stickRadius", "Full stick radius (surface fraction)", $draft.stickRadius)
            field("deadzone", "Stick deadzone", $draft.deadzone)
          }
        }
      }
    }

    private func field(_ key: String, _ fallback: String, _ value: Binding<String>) -> some View {
      VStack(alignment: .leading, spacing: 4) {
        Text(label(key, fallback))
        TextField(label(key, fallback), text: value).textFieldStyle(RoundedBorderTextFieldStyle())
      }
    }

    private func label(_ key: String, _ fallback: String) -> String {
      OJDLocalized.string("profiles.touch." + key, fallback: fallback)
    }
  }
#endif
