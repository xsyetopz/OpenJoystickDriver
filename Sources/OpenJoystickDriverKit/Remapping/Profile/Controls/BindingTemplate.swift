/// A profile template that binds controls by their standard names.
public enum RemappingBindingTemplate: String, CaseIterable, Sendable {
  /// The D-pad presses the arrow keys, South presses Return and East presses Escape.
  case keyboardNavigation
  /// South, East and North press the left, right and middle mouse buttons.
  case mouseClicks

  /// A profile made from a template, with the controls it could not bind.
  public struct Made: Equatable, Sendable {
    /// The profile; it binds the template's controls that the controller has.
    public let profile: RemappingProfile
    /// The controls of the template that the controller lacks, in template order.
    public let skipped: [Control]
  }

  /// The controls the template binds, in order, each with its destination.
  private var entries: [(control: Control, destination: RemappingDestination)] {
    switch self {
    case .keyboardNavigation:
      [
        (.dpadUp, .keyboard(key: .arrowUp, modifiers: [])),
        (.dpadDown, .keyboard(key: .arrowDown, modifiers: [])),
        (.dpadLeft, .keyboard(key: .arrowLeft, modifiers: [])),
        (.dpadRight, .keyboard(key: .arrowRight, modifiers: [])),
        (.south, .keyboard(key: .returnKey, modifiers: [])),
        (.east, .keyboard(key: .escape, modifiers: [])),
      ]
    case .mouseClicks:
      [
        (.south, .mouseButton(.left)),
        (.east, .mouseButton(.right)),
        (.north, .mouseButton(.middle)),
      ]
    }
  }

  /// The controls the template binds, in order.
  public var controls: [Control] { entries.map(\.control) }

  /// Makes a profile that binds each control of the template that `capabilities` report, and lists
  /// the others in ``Made/skipped``.
  public func profile(
    name: String,
    device: RemappingDeviceScope,
    applicationScope: RemappingApplicationScope,
    outputPolicy: RemappingOutputPolicy,
    capabilities: ControllerProfileCapabilities
  ) -> Made {
    let present = capabilities.physicalInput.controls
    let bound = entries.filter { present.contains($0.control) }
    return Made(
      profile: RemappingProfile(
        name: name,
        device: device,
        applicationScope: applicationScope,
        outputPolicy: outputPolicy,
        bindings: bound.map {
          RemappingBinding(source: Self.source(of: $0.control), destination: $0.destination)
        }
      ),
      skipped: entries.map(\.control).filter { !present.contains($0) }
    )
  }

  /// The source of a control: a D-pad direction for a D-pad control, else a button.
  private static func source(of control: Control) -> RemappingSource {
    switch control {
    case .dpadUp: .dpad(.up)
    case .dpadDown: .dpad(.down)
    case .dpadLeft: .dpad(.left)
    case .dpadRight: .dpad(.right)
    default: .button(control)
    }
  }
}
