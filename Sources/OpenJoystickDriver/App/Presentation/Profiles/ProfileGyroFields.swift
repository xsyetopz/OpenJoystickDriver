#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileGyroFields: View {
    @Binding
    var draft: ProfileGyroDraft

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Picker(label("output", "Gyro output"), selection: $draft.mode) {
          Text(label("disabled", "Disabled")).tag(RemappingGyroOutputMode.disabled)
          Text(label("mouse", "Mouse pointer")).tag(RemappingGyroOutputMode.mouse)
          Text(label("leftStick", "Left stick")).tag(RemappingGyroOutputMode.leftStick)
          Text(label("rightStick", "Right stick")).tag(RemappingGyroOutputMode.rightStick)
        }
        Toggle(
          label("virtualMotion", "Forward calibrated virtual motion"),
          isOn: $draft.virtualMotion
        )
        if draft.mode != .disabled {
          ProfileTrackballFields(draft: $draft.trackball)
          if draft.mode == .mouse {
            TextField(
              label("pointerScale", "Pointer points per degree"),
              text: $draft.pointerPointsPerDegree
            )
          } else {
            TextField(
              label("stickScale", "Full stick speed (degrees/s)"),
              text: $draft.fullStickDegreesPerSecond
            )
          }
          Picker(label("activation", "Gyro activation"), selection: $draft.activationMode) {
            Text(label("always", "Always active")).tag(RemappingGyroActivationMode.always)
            Text(label("whileHeld", "While held")).tag(RemappingGyroActivationMode.whileHeld)
            Text(label("whileReleased", "While released")).tag(
              RemappingGyroActivationMode.whileReleased
            )
            Text(label("toggle", "Toggle on press")).tag(RemappingGyroActivationMode.toggle)
          }
          if draft.activationMode != .always {
            Toggle(
              label("consume", "Suppress original virtual activation control"),
              isOn: $draft.consumesActivationSource
            )
            Picker(label("source", "Activation control"), selection: $draft.activationSource) {
              ForEach(sources, id: \.source) { option in Text(option.title).tag(option.source) }
            }
          }
        }
      }
    }

    private var sources: [SourceOption] {
      SourceOption.options(including: draft.activationSource).filter {
        if case .axis = $0.source { return false }
        return true
      }
    }

    private func label(_ key: String, _ fallback: String) -> String {
      OJDLocalized.string("profiles.gyro." + key, fallback: fallback)
    }
  }
#endif
