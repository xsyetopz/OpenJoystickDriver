#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileTrackballFields: View {
    @Binding
    var draft: ProfileTrackballDraft

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Toggle(label("enabled"), isOn: $draft.enabled)
        if draft.enabled {
          Text(
            label("hint")
          ).font(.caption)
          Picker(label("source"), selection: $draft.source) {
            ForEach(sources, id: \.source) { option in Text(option.title).tag(option.source) }
          }
          Picker(label("axes"), selection: $draft.axes) {
            Text(label("pitch")).tag(RemappingGyroTrackballAxes.pitch)
            Text(label("yaw")).tag(RemappingGyroTrackballAxes.yaw)
            Text(label("both")).tag(RemappingGyroTrackballAxes.both)
          }
          TextField(label("decay"), text: $draft.decay)
          Text(label("decayHint"))
            .font(.caption)
          Toggle(
            label("consume"),
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

    private func label(_ key: String) -> String {
      OJDLocalized.string("profiles.trackball." + key)
    }
  }
#endif
