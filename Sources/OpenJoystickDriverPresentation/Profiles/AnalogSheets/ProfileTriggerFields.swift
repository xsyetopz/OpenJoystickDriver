#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileTriggerFields: View {
    @Binding
    var draft: ProfileTriggerDraft

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Toggle(label("enabled"), isOn: $draft.enabled)
        if draft.enabled {
          Picker(label("mode"), selection: $draft.mode) {
            ForEach(RemappingDualStageTriggerMode.allCases, id: \.self) { mode in
              Text(modeLabel(mode)).tag(mode)
            }
          }
          field("softThreshold", $draft.softThreshold)
          field("fullThreshold", $draft.fullThreshold)
          field("hysteresis", $draft.hysteresis)
          if draft.mode.buffersSoftPull {
            field("skipWindow", $draft.skipWindowMs)
          }
          Toggle(label("passthrough"), isOn: $draft.passthrough)
        }
      }
    }

    private func field(_ key: String, _ value: Binding<String>) -> some View {
      VStack(alignment: .leading, spacing: 4) {
        Text(label(key))
        TextField(label(key), text: value).textFieldStyle(RoundedBorderTextFieldStyle())
      }
    }

    private func modeLabel(_ mode: RemappingDualStageTriggerMode) -> String {
      switch mode {
      case .simultaneous: return label("simultaneous")
      case .exclusive: return label("exclusive")
      case .preferFull: return label("preferFull")
      case .preferFullCombined:
        return label("preferFullCombined")
      case .responsivePreferFull:
        return label("responsivePreferFull")
      case .responsivePreferFullCombined:
        return label("responsivePreferFullCombined")
      }
    }

    private func label(_ key: String) -> String {
      OJDLocalized.string("profiles.trigger." + key)
    }
  }
#endif
