#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  /// The gyro output fields of the motion sheet: the output, its scale, the trackball and the
  /// activation.
  struct ProfileGyroFields: View {
    /// The gyro output being edited.
    @Binding
    var draft: ProfileGyroDraft

    /// The gyro output picker and the fields of the chosen output.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.medium) {
        Picker(label("output"), selection: $draft.mode) {
          Text(label("disabled")).tag(RemappingGyroOutputMode.disabled)
          Text(label("mouse")).tag(RemappingGyroOutputMode.mouse)
          Text(label("leftStick")).tag(RemappingGyroOutputMode.leftStick)
          Text(label("rightStick")).tag(RemappingGyroOutputMode.rightStick)
        }
        if draft.mode != .disabled {
          ProfileTrackballFields(draft: $draft.trackball)
          if draft.mode == .mouse {
            TextField(
              label("pointerScale"),
              text: $draft.pointerPointsPerDegree
            ).ojdAccessibilityLabel(label("pointerScale"))
          } else {
            TextField(
              label("stickScale"),
              text: $draft.fullStickDegreesPerSecond
            ).ojdAccessibilityLabel(label("stickScale"))
          }
          Picker(label("activation"), selection: $draft.activationMode) {
            Text(label("always")).tag(RemappingGyroActivationMode.always)
            Text(label("whileHeld")).tag(RemappingGyroActivationMode.whileHeld)
            Text(label("whileReleased")).tag(
              RemappingGyroActivationMode.whileReleased
            )
            Text(label("toggle")).tag(RemappingGyroActivationMode.toggle)
          }
          if draft.activationMode != .always {
            Toggle(
              label("consume"),
              isOn: $draft.consumesActivationSource
            )
            Picker(label("source"), selection: $draft.activationSource) {
              ForEach(sources, id: \.source) { option in Text(option.title).tag(option.source) }
            }
          }
        }
      }
    }

    /// The sources that can activate the gyro output; an axis cannot.
    private var sources: [SourceOption] {
      SourceOption.options(including: draft.activationSource).filter {
        if case .axis = $0.source { return false }
        return true
      }
    }

    /// Returns the text of the gyro field called `key`.
    private func label(_ key: String) -> String {
      OJDLocalized.string("ui.profiles.gyro." + key)
    }
  }
#endif
