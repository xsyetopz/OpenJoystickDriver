#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileStickFields: View {
    @Binding var draft: ProfileStickDraft

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Toggle(label("enabled", "Enable pointer output"), isOn: $draft.enabled)
        if draft.enabled {
          Picker(label("mode", "Stick mode"), selection: $draft.mode) {
            Text(label("aim", "Aim")).tag(RemappingStickMode.aim)
            Text(label("flick", "Flick and rotate")).tag(RemappingStickMode.flick)
            Text(label("flickOnly", "Flick only")).tag(RemappingStickMode.flickOnly)
            Text(label("rotateOnly", "Rotate only")).tag(RemappingStickMode.rotateOnly)
            Text(label("pointerArea", "Pointer area")).tag(RemappingStickMode.pointerArea)
            Text(label("pointerRing", "Pointer ring")).tag(RemappingStickMode.pointerRing)
            Text(label("scrollWheel", "Scroll wheel")).tag(RemappingStickMode.scrollWheel)
            Text(label("steering", "Steering wheel")).tag(RemappingStickMode.steering)
          }
          field("innerDeadzone", "Inner deadzone", $draft.innerDeadzone)
          field("outerDeadzone", "Outer deadzone", $draft.outerDeadzone)
          field("exponent", "Response exponent", $draft.responseExponent)
          Toggle(label("invertX", "Invert horizontal axis"), isOn: $draft.invertX)
          Toggle(label("invertY", "Invert vertical axis"), isOn: $draft.invertY)
          if [.aim, .flick, .flickOnly, .rotateOnly].contains(draft.mode) {
            field("pointerScale", "Pointer points per degree", $draft.pointerPointsPerDegree)
          }
          if draft.mode == .aim {
            field("aimRate", "Aim speed (degrees/s)", $draft.aimDegreesPerSecond)
          } else if [.flick, .flickOnly, .rotateOnly].contains(draft.mode) {
            if draft.mode != .rotateOnly {
              field("flickDuration", "Flick duration (ms)", $draft.flickDurationMs)
            }
            field("threshold", "Flick engagement threshold", $draft.flickThreshold)
            field("hysteresis", "Flick release hysteresis", $draft.flickHysteresis)
          } else if draft.mode == .pointerArea || draft.mode == .pointerRing {
            field("pointerRadius", "Pointer radius (points)", $draft.pointerRadiusPoints)
          } else if draft.mode == .scrollWheel {
            field(
              "scrollDegrees", "Rotation per scroll line (degrees)", $draft.scrollDegreesPerLine
            )
            Picker(label("scrollAxis", "Scroll axis"), selection: $draft.scrollAxis) {
              Text(label("horizontal", "Horizontal")).tag(RemappingStickScrollAxis.horizontal)
              Text(label("vertical", "Vertical")).tag(RemappingStickScrollAxis.vertical)
            }
            rotationPicker
          } else if draft.mode == .steering {
            field(
              "steeringFullScale",
              "Rotation at full steering (degrees)",
              $draft.steeringDegreesAtFullScale
            )
            field(
              "steeringReturnRate",
              "Steering return speed (degrees/s)",
              $draft.steeringReturnDegreesPerSecond
            )
            Picker(
              label("steeringOutput", "Virtual steering axis"), selection: $draft.steeringOutput
            ) {
              Text(label("leftStickX", "Left stick horizontal")).tag(
                RemappingStickSteeringOutput.leftStickX
              )
              Text(label("rightStickX", "Right stick horizontal")).tag(
                RemappingStickSteeringOutput.rightStickX
              )
            }
            rotationPicker
          }
          Toggle(label("passthrough", "Keep physical stick passthrough"), isOn: $draft.passthrough)
        }
      }
    }

    private var rotationPicker: some View {
      Picker(label("rotationDirection", "Positive rotation"), selection: $draft.rotationDirection) {
        Text(label("clockwise", "Clockwise")).tag(RemappingStickRotationDirection.clockwise)
        Text(label("counterclockwise", "Counterclockwise")).tag(
          RemappingStickRotationDirection.counterclockwise
        )
      }
    }

    private func field(_ key: String, _ fallback: String, _ value: Binding<String>) -> some View {
      VStack(alignment: .leading, spacing: 4) {
        Text(label(key, fallback))
        TextField(label(key, fallback), text: value).textFieldStyle(RoundedBorderTextFieldStyle())
      }
    }

    private func label(_ key: String, _ fallback: String) -> String {
      OJDLocalized.string("profiles.stick." + key, fallback: fallback)
    }
  }
#endif
