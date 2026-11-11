#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  /// The fields of the gyro trackball: the source, axes, decay and whether it consumes the source.
  struct ProfileTrackballFields: View {
    /// The trackball being edited.
    @Binding
    var draft: ProfileTrackballDraft

    /// The enabled toggle and, while it is on, the source and the settings of the trackball.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.medium) {
        Toggle(label("enabled"), isOn: $draft.enabled)
        if draft.enabled {
          Text(
            label("hint")
          ).font(.body)
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
            .font(.body)
          Toggle(
            label("consume"),
            isOn: $draft.consumesSource
          )
        }
      }
    }

    /// The sources that can drive the trackball; an axis cannot.
    private var sources: [SourceOption] {
      SourceOption.options(including: draft.source).filter {
        if case .axis = $0.source { return false }
        return true
      }
    }

    /// Returns the text of the trackball field called `key`.
    private func label(_ key: String) -> String {
      OJDLocalized.string("ui.profiles.trackball." + key)
    }
  }
#endif
