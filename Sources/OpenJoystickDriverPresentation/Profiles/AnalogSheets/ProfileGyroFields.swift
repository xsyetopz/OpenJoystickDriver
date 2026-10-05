#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileGyroFields: View {
    @Binding
    var draft: ProfileGyroDraft

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
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
            )
          } else {
            TextField(
              label("stickScale"),
              text: $draft.fullStickDegreesPerSecond
            )
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

    private var sources: [SourceOption] {
      SourceOption.options(including: draft.activationSource).filter {
        if case .axis = $0.source { return false }
        return true
      }
    }

    private func label(_ key: String) -> String {
      OJDLocalized.string("profiles.gyro." + key)
    }
  }
#endif
