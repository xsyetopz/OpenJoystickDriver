#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileTriggerFields: View {
    @Binding var draft: ProfileTriggerDraft

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Toggle(label("enabled", "Enable dual-stage trigger"), isOn: $draft.enabled)
        if draft.enabled {
          Picker(label("mode", "Stage interaction"), selection: $draft.mode) {
            ForEach(RemappingDualStageTriggerMode.allCases, id: \.self) { mode in
              Text(modeLabel(mode)).tag(mode)
            }
          }
          field("softThreshold", "Soft-pull threshold (0...1)", $draft.softThreshold)
          field("fullThreshold", "Full-pull threshold (0...1)", $draft.fullThreshold)
          field("hysteresis", "Release hysteresis", $draft.hysteresis)
          if draft.mode.buffersSoftPull {
            field("skipWindow", "Quick-pull window (ms)", $draft.skipWindowMs)
          }
          Toggle(
            label("passthrough", "Keep analog trigger passthrough"),
            isOn: $draft.passthrough
          )
        }
      }
    }

    private func field(_ key: String, _ fallback: String, _ value: Binding<String>) -> some View {
      VStack(alignment: .leading, spacing: 4) {
        Text(label(key, fallback))
        TextField(label(key, fallback), text: value).textFieldStyle(RoundedBorderTextFieldStyle())
      }
    }

    private func modeLabel(_ mode: RemappingDualStageTriggerMode) -> String {
      switch mode {
      case .simultaneous: return label("simultaneous", "Soft and full together")
      case .exclusive: return label("exclusive", "Full replaces soft")
      case .preferFull: return label("preferFull", "Prefer quick full")
      case .preferFullCombined:
        return label("preferFullCombined", "Prefer quick full; combine late")
      case .responsivePreferFull:
        return label("responsivePreferFull", "Responsive soft; prefer quick full")
      case .responsivePreferFullCombined:
        return label("responsivePreferFullCombined", "Responsive soft; combine late")
      }
    }

    private func label(_ key: String, _ fallback: String) -> String {
      OJDLocalized.string("profiles.trigger." + key, fallback: fallback)
    }
  }
#endif
