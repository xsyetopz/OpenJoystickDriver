#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  /// The fields of one trigger mapping: the dual-stage mode, the thresholds and pass-through.
  struct ProfileTriggerFields: View {
    /// The trigger mapping being edited.
    @Binding
    var draft: ProfileTriggerDraft

    /// The enabled toggle and, while it is on, the mode and the settings of the trigger.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.medium) {
        Toggle(label("enabled"), isOn: $draft.enabled).help(tooltip("enabled"))
        if draft.enabled {
          Picker(label("mode"), selection: $draft.mode) {
            ForEach(RemappingDualStageTriggerMode.allCases, id: \.self) { mode in
              Text(modeLabel(mode)).tag(mode)
            }
          }.help(tooltip("mode"))
          field("softThreshold", $draft.softThreshold)
          field("fullThreshold", $draft.fullThreshold)
          field("hysteresis", $draft.hysteresis)
          if draft.mode.buffersSoftPull {
            field("skipWindow", $draft.skipWindowMs)
          }
          Toggle(label("passthrough"), isOn: $draft.passthrough).help(tooltip("passthrough"))
        }
      }
    }

    /// A labeled text field for the trigger setting called `key`.
    private func field(_ key: String, _ value: Binding<String>) -> some View {
      VStack(alignment: .leading, spacing: OJDSpacing.xSmall) {
        Text(label(key))
        TextField(label(key), text: value).textFieldStyle(RoundedBorderTextFieldStyle())
          .ojdAccessibilityLabel(label(key)).help(tooltip(key))
      }
    }

    /// Returns the name of a dual-stage trigger mode.
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

    /// Returns the text of the trigger field called `key`.
    private func label(_ key: String) -> String {
      OJDLocalized.string("ui.profiles.trigger." + key)
    }

    /// Returns the tooltip of the trigger field called `key`.
    private func tooltip(_ key: String) -> String {
      OJDLocalized.string("ui.profiles.trigger." + key + "Help")
    }
  }
#endif
