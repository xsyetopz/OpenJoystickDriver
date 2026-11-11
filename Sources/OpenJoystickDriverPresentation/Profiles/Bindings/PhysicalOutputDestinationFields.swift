#if canImport(SwiftUI)
  import OpenJoystickDriverKit
  import SwiftUI

  /// The fields of a physical output destination (the rumble motor and intensity, the player
  /// indicator, the color, the brightness, or the adaptive trigger) or of a `Speak` destination.
  struct PhysicalOutputDestinationFields: View {
    /// The destination being edited; the fields show only for a physical output or a `Speak`.
    @Binding
    var destination: RemappingDestination

    /// The fields of a physical output or `Speak` destination; nothing for any other destination.
    var body: some View {
      if case .physical(let output) = destination {
        VStack(alignment: .leading, spacing: OJDSpacing.small) {
          switch output {
          case .rumble(let motor, let intensity):
            Picker(
              OJDLocalized.string("ui.profiles.physical.motor"),
              selection: rumbleMotor(motor, intensity: intensity)
            ) {
              ForEach(PhysicalRumbleMotor.allCases, id: \.self) {
                Text(RuntimePresentation.upperCamelWords($0.rawValue)).tag($0)
              }
            }
            unitSlider(
              OJDLocalized.string("ui.profiles.physical.intensity"),
              value: rumbleIntensity(motor, intensity: intensity)
            )
          case .playerIndicator(let indicator):
            Picker(
              OJDLocalized.string("ui.profiles.physical.player"),
              selection: playerIndicator(indicator)
            ) {
              ForEach(PhysicalPlayerIndicator.allCases, id: \.self) {
                Text(
                  $0 == .off
                    ? OJDLocalized.string("status.disabled")
                    : String($0.rawValue)
                ).tag($0)
              }
            }
          case .color(let color):
            colorSlider(
              OJDLocalized.string("ui.profiles.physical.red"),
              value: colorComponent(color, component: 0)
            )
            colorSlider(
              OJDLocalized.string("ui.profiles.physical.green"),
              value: colorComponent(color, component: 1)
            )
            colorSlider(
              OJDLocalized.string("ui.profiles.physical.blue"),
              value: colorComponent(color, component: 2)
            )
          case .brightness(let intensity):
            unitSlider(
              OJDLocalized.string("ui.profiles.physical.brightness"),
              value: brightness(intensity)
            )
          case .adaptiveTrigger(let trigger, let effect):
            Picker(
              OJDLocalized.string("ui.profiles.physical.trigger"),
              selection: adaptiveTrigger(trigger, effect: effect)
            ) {
              ForEach(PhysicalAdaptiveTrigger.allCases, id: \.self) {
                Text(RuntimePresentation.humanized($0.rawValue)).tag($0)
              }
            }
            Picker(
              OJDLocalized.string("ui.profiles.physical.effect"),
              selection: adaptiveKind(trigger, effect: effect)
            ) {
              ForEach(PhysicalAdaptiveTriggerEffectKind.allCases, id: \.self) {
                Text(RuntimePresentation.humanized($0.rawValue)).tag($0)
              }
            }
            if effect.kind == .resistance {
              unitSlider(
                OJDLocalized.string(
                  "ui.profiles.physical.startPosition"
                ),
                value: adaptiveStart(trigger, effect: effect)
              )
              unitSlider(
                OJDLocalized.string("ui.profiles.physical.strength"),
                value: adaptiveStrength(trigger, effect: effect)
              )
            }
          }
        }.padding(.leading, 8)
      } else if let field = valueField {
        TextField(field.title, text: field.text).padding(.leading, 8)
      } else if case .speak(let text, let voice) = destination {
        VStack(alignment: .leading, spacing: OJDSpacing.small) {
          TextField(
            OJDLocalized.string("ui.profiles.speak.text"),
            text: Binding(
              get: { text },
              set: {
                destination = .speak(
                  text: String(String.UnicodeScalarView($0.unicodeScalars.prefix(128))),
                  voice: voice
                )
              }
            )
          )
          TextField(
            OJDLocalized.string("ui.profiles.speak.voice"),
            text: Binding(
              get: { voice ?? "" },
              set: { destination = .speak(text: text, voice: $0.isEmpty ? nil : $0) }
            ),
            prompt: Text(OJDLocalized.string("ui.profiles.speak.voicePlaceholder"))
          )
        }.padding(.leading, 8)
      }
    }

    /// The title and text of the one value that an open application, open URL, run Shortcut or type
    /// text destination holds; `nil` for any other destination.
    private var valueField: (title: String, text: Binding<String>)? {
      switch destination {
      case .openApplication(let value):
        (
          OJDLocalized.string("ui.profiles.system.application"),
          Binding(get: { value }, set: { destination = .openApplication(bundleIdentifier: $0) })
        )
      case .openURL(let value):
        (
          OJDLocalized.string("ui.profiles.system.url"),
          Binding(get: { value }, set: { destination = .openURL($0) })
        )
      case .runShortcut(let value):
        (
          OJDLocalized.string("ui.profiles.system.shortcut"),
          Binding(get: { value }, set: { destination = .runShortcut($0) })
        )
      case .typeText(let value):
        (
          OJDLocalized.string("ui.profiles.speak.text"),
          Binding(get: { value }, set: { destination = .typeText($0) })
        )
      default: nil
      }
    }

    /// Returns a binding that sets the motor of a rumble destination and keeps `intensity`.
    private func rumbleMotor(
      _ motor: PhysicalRumbleMotor,
      intensity: Double
    ) -> Binding<PhysicalRumbleMotor> {
      Binding(
        get: { motor },
        set: { destination = .physical(.rumble(motor: $0, intensity: intensity)) }
      )
    }

    /// Returns a binding that sets the intensity of a rumble destination and keeps `motor`.
    private func rumbleIntensity(_ motor: PhysicalRumbleMotor, intensity: Double) -> Binding<Double>
    {
      Binding(
        get: { intensity },
        set: { destination = .physical(.rumble(motor: motor, intensity: $0)) }
      )
    }

    /// Returns a binding that sets the player indicator.
    private func playerIndicator(
      _ indicator: PhysicalPlayerIndicator
    ) -> Binding<PhysicalPlayerIndicator> {
      Binding(get: { indicator }, set: { destination = .physical(.playerIndicator($0)) })
    }

    /// Returns a binding to one color component, `0` for red, `1` for green and `2` for blue.
    private func colorComponent(_ color: ControllerColor, component: Int) -> Binding<Double> {
      Binding(
        get: { Double([color.red, color.green, color.blue][component]) },
        set: { value in
          var values = [color.red, color.green, color.blue]
          values[component] = UInt8(value.rounded())
          destination = .physical(
            .color(ControllerColor(red: values[0], green: values[1], blue: values[2]))
          )
        }
      )
    }

    /// Returns a binding that sets the brightness.
    private func brightness(_ intensity: Double) -> Binding<Double> {
      Binding(get: { intensity }, set: { destination = .physical(.brightness($0)) })
    }

    /// Returns a binding that sets the trigger of an adaptive trigger destination and keeps
    /// `effect`.
    private func adaptiveTrigger(
      _ trigger: PhysicalAdaptiveTrigger,
      effect: PhysicalAdaptiveTriggerEffect
    ) -> Binding<PhysicalAdaptiveTrigger> {
      Binding(get: { trigger }, set: { destination = .physical(.adaptiveTrigger($0, effect)) })
    }

    /// Returns a binding that sets the effect kind: Off, or resistance with the start position
    /// and strength of `effect`.
    private func adaptiveKind(
      _ trigger: PhysicalAdaptiveTrigger,
      effect: PhysicalAdaptiveTriggerEffect
    ) -> Binding<PhysicalAdaptiveTriggerEffectKind> {
      Binding(
        get: { effect.kind },
        set: { kind in
          destination = .physical(
            .adaptiveTrigger(
              trigger,
              kind == .off
                ? .off
                : PhysicalAdaptiveTriggerEffect(
                  kind: .resistance,
                  startPosition: effect.startPosition,
                  strength: effect.strength
                )
            )
          )
        }
      )
    }

    /// Returns a binding to the start position of the resistance effect.
    private func adaptiveStart(
      _ trigger: PhysicalAdaptiveTrigger,
      effect: PhysicalAdaptiveTriggerEffect
    ) -> Binding<Double> {
      Binding(
        get: { effect.startPosition },
        set: {
          destination = .physical(
            .adaptiveTrigger(
              trigger,
              PhysicalAdaptiveTriggerEffect(
                kind: .resistance,
                startPosition: $0,
                strength: effect.strength
              )
            )
          )
        }
      )
    }

    /// Returns a binding to the strength of the resistance effect.
    private func adaptiveStrength(
      _ trigger: PhysicalAdaptiveTrigger,
      effect: PhysicalAdaptiveTriggerEffect
    ) -> Binding<Double> {
      Binding(
        get: { effect.strength },
        set: {
          destination = .physical(
            .adaptiveTrigger(
              trigger,
              PhysicalAdaptiveTriggerEffect(
                kind: .resistance,
                startPosition: effect.startPosition,
                strength: $0
              )
            )
          )
        }
      )
    }

    /// A slider from 0 to 1 that shows the value as a percentage beside `title`.
    private func unitSlider(_ title: String, value: Binding<Double>) -> some View {
      VStack(alignment: .leading, spacing: OJDSpacing.xSmall) {
        Text("\(title): \(Int((value.wrappedValue * 100).rounded()))%").font(.body)
        Slider(value: value, in: 0...1).ojdAccessibilityLabel(title)
      }
    }

    /// A slider from 0 to 255 that shows the value beside `title`.
    private func colorSlider(_ title: String, value: Binding<Double>) -> some View {
      VStack(alignment: .leading, spacing: OJDSpacing.xSmall) {
        Text("\(title): \(Int(value.wrappedValue.rounded()))").font(.body)
        Slider(value: value, in: 0...255).ojdAccessibilityLabel(title)
      }
    }
  }
#endif
