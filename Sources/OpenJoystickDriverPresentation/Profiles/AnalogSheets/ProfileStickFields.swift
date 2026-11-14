#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  /// The fields of one stick mapping: the mode, the dead zones, the response and the settings of
  /// the mode.
  struct ProfileStickFields: View {
    /// The stick mapping being edited.
    @Binding
    var draft: ProfileStickDraft

    /// The enabled toggle and, while it is on, the mode and the settings of the stick.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.medium) {
        Toggle(label("enabled"), isOn: $draft.enabled).help(tooltip("enabled"))
        if draft.enabled {
          Picker(label("mode"), selection: $draft.mode) {
            Text(label("aim")).tag(RemappingStickMode.aim)
            Text(label("flick")).tag(RemappingStickMode.flick)
            Text(label("flickOnly")).tag(RemappingStickMode.flickOnly)
            Text(label("rotateOnly")).tag(RemappingStickMode.rotateOnly)
            Text(label("pointerArea")).tag(RemappingStickMode.pointerArea)
            Text(label("pointerRing")).tag(RemappingStickMode.pointerRing)
            Text(label("scrollWheel")).tag(RemappingStickMode.scrollWheel)
            Text(label("steering")).tag(RemappingStickMode.steering)
          }.help(tooltip("mode"))
          field("innerDeadzone", $draft.innerDeadzone)
          field("outerDeadzone", $draft.outerDeadzone)
          field("exponent", $draft.responseExponent)
          Toggle(label("invertX"), isOn: $draft.invertX).help(tooltip("invertX"))
          Toggle(label("invertY"), isOn: $draft.invertY).help(tooltip("invertY"))
          if [.aim, .flick, .flickOnly, .rotateOnly].contains(draft.mode) {
            field("pointerScale", $draft.pointerPointsPerDegree)
          }
          if draft.mode == .aim {
            field("aimRate", $draft.aimDegreesPerSecond)
          } else if [.flick, .flickOnly, .rotateOnly].contains(draft.mode) {
            if draft.mode != .rotateOnly {
              field("flickDuration", $draft.flickDurationMs)
            }
            field("threshold", $draft.flickThreshold)
            field("hysteresis", $draft.flickHysteresis)
          } else if draft.mode == .pointerArea || draft.mode == .pointerRing {
            field("pointerRadius", $draft.pointerRadiusPoints)
          } else if draft.mode == .scrollWheel {
            field(
              "scrollDegrees",
              $draft.scrollDegreesPerLine
            )
            Picker(label("scrollAxis"), selection: $draft.scrollAxis) {
              Text(label("horizontal")).tag(RemappingStickScrollAxis.horizontal)
              Text(label("vertical")).tag(RemappingStickScrollAxis.vertical)
            }.help(tooltip("scrollAxis"))
            rotationPicker
          } else if draft.mode == .steering {
            field(
              "steeringFullScale",
              $draft.steeringDegreesAtFullScale
            )
            field(
              "steeringReturnRate",
              $draft.steeringReturnDegreesPerSecond
            )
            Picker(
              label("steeringOutput"),
              selection: $draft.steeringOutput
            ) {
              Text(label("leftStickX")).tag(
                RemappingStickSteeringOutput.leftStickX
              )
              Text(label("rightStickX")).tag(
                RemappingStickSteeringOutput.rightStickX
              )
            }.help(tooltip("steeringOutput"))
            rotationPicker
          }
          Toggle(label("passthrough"), isOn: $draft.passthrough).help(tooltip("passthrough"))
        }
      }
    }

    /// The picker of the rotation direction.
    private var rotationPicker: some View {
      Picker(label("rotationDirection"), selection: $draft.rotationDirection) {
        Text(label("clockwise")).tag(RemappingStickRotationDirection.clockwise)
        Text(label("counterclockwise")).tag(
          RemappingStickRotationDirection.counterclockwise
        )
      }.help(tooltip("rotationDirection"))
    }

    /// A labeled text field for the stick setting called `key`.
    private func field(_ key: String, _ value: Binding<String>) -> some View {
      VStack(alignment: .leading, spacing: OJDSpacing.xSmall) {
        Text(label(key))
        TextField(label(key), text: value).textFieldStyle(RoundedBorderTextFieldStyle())
          .ojdAccessibilityLabel(label(key)).help(tooltip(key))
      }
    }

    /// Returns the text of the stick field called `key`.
    private func label(_ key: String) -> String {
      OJDLocalized.string("ui.profiles.stick." + key)
    }

    /// Returns the tooltip of the stick field called `key`.
    private func tooltip(_ key: String) -> String {
      OJDLocalized.string("ui.profiles.stick." + key + "Help")
    }
  }
#endif
