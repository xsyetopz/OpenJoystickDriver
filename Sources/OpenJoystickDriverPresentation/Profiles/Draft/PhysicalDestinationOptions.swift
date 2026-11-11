import OpenJoystickDriverKit

extension DestinationOption {
  /// The physical output destinations the destination pickers list: each rumble motor at full
  /// intensity, each player indicator but off, four colors, full brightness and each adaptive
  /// trigger with a resistance effect.
  static let physical: [Self] = {
    let destinations: [RemappingDestination] =
      PhysicalRumbleMotor.allCases.map { .physical(.rumble(motor: $0, intensity: 1)) }
      + PhysicalPlayerIndicator.allCases.filter { $0 != .off }.map {
        .physical(.playerIndicator($0))
      } + [
        .physical(.color(ControllerColor(red: 255, green: 0, blue: 0))),
        .physical(.color(ControllerColor(red: 0, green: 255, blue: 0))),
        .physical(.color(ControllerColor(red: 0, green: 0, blue: 255))),
        .physical(.color(ControllerColor(red: 255, green: 255, blue: 255))),
        .physical(.brightness(1)),
      ]
      + PhysicalAdaptiveTrigger.allCases.map {
        .physical(
          .adaptiveTrigger(
            $0,
            PhysicalAdaptiveTriggerEffect(kind: .resistance, startPosition: 0.5, strength: 0.75)
          )
        )
      }
    return destinations.map {
      Self(destination: $0, title: RuntimePresentation.destinationLabel($0), isSupported: true)
    }
  }()
}
