#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileTrackballFields: View {
    @Binding var draft: ProfileTrackballDraft

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Toggle(label("enabled", "Trackball"), isOn: $draft.enabled)
        if draft.enabled {
          Text(label(
            "hint", "Hold the control to continue motion while repositioning the controller."
          ))
            .font(.caption)
          Picker(label("source", "Trackball control"), selection: $draft.source) {
            ForEach(sources, id: \.source) { option in
              Text(option.title).tag(option.source)
            }
          }
          Picker(label("axes", "Trackball axes"), selection: $draft.axes) {
            Text(label("pitch", "Pitch")).tag(RemappingGyroTrackballAxes.pitch)
            Text(label("yaw", "Yaw")).tag(RemappingGyroTrackballAxes.yaw)
            Text(label("both", "Pitch and yaw")).tag(RemappingGyroTrackballAxes.both)
          }
          TextField(label("decay", "Velocity halvings per second"), text: $draft.decay)
          Text(label("decayHint", "Zero keeps a constant speed. One halves the speed each second."))
            .font(.caption)
          Toggle(
            label("consume", "Suppress original virtual trackball control"),
            isOn: $draft.consumesSource
          )
        }
      }
    }

    private var sources: [SourceOption] {
      SourceOption.options(including: draft.source).filter {
        if case .axis = $0.source { return false }
        return true
      }
    }

    private func label(_ key: String, _ fallback: String) -> String {
      OJDLocalized.string("profiles.trackball." + key, fallback: fallback)
    }
  }
#endif
