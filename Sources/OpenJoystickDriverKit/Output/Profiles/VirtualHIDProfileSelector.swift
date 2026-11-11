/// Chooses the one virtual HID profile a logical controller publishes: the Advanced override when
/// the controller fits it, else `SDLCompatible` when the controller's primary controls fit it,
/// else `Generic`.
///
/// Selection reads only the controller's declared controls and the user's Advanced override.
/// Protocol, manufacturer, consumer, macOS version, and access backend never participate, and a
/// natively passed-through controller never reaches selection. Only ``ServingPolicy`` calls it.
public enum VirtualHIDProfileSelector {
  /// The outcome of selection.
  public struct Selection: Equatable, Sendable {
    /// How the profile was chosen.
    public enum Source: Equatable, Sendable {
      /// Automatic selection chose it.
      case automatic
      /// The Advanced override chose it.
      case override
      /// The controller could not satisfy this override, so automatic selection ran instead.
      case automaticAfterRejecting(VirtualHIDProfileID)
    }

    /// The selected profile.
    public let profileID: VirtualHIDProfileID
    /// How the profile was chosen.
    public let source: Source
  }

  /// Controls whose representation decides the profile: the Xbox layout plus the digital trigger
  /// buttons.
  ///
  /// System controls other than `view` and `menu`, and every extended control, stay in OJD's
  /// normalized API and never force a persona.
  public static let primaryControls: Set<Control> = Control.xboxLayout.union([
    .leftTrigger, .rightTrigger,
  ])

  /// The profiles automatic selection tries, in order.
  static let automaticOrder: [VirtualHIDProfileID] = [.sdlCompatible, .generic]

  /// Selects the profile for a controller that declares `controls`.
  ///
  /// - Throws: `ProtocolBindingReason.virtualProfileUnavailable` when the selected profile cannot
  ///   represent the controller's primary controls.
  static func select(
    controls: Set<Control>,
    override: VirtualHIDProfileID?
  ) throws(ProtocolBindingReason) -> Selection {
    try select(controls: controls, override: override, slots: \.representableControls)
  }

  /// `select(controls:override:)` over explicit profile slots, so tests can reach the branches that
  /// the two profiles never take.
  static func select(
    controls: Set<Control>,
    override: VirtualHIDProfileID?,
    slots: (VirtualHIDProfileID) -> Set<Control>
  ) throws(ProtocolBindingReason) -> Selection {
    let required = controls.intersection(primaryControls)
    func fits(_ profile: VirtualHIDProfileID) -> Bool { represents(required, in: slots(profile)) }
    if let override, fits(override) { return Selection(profileID: override, source: .override) }
    // SDL 3.4.12 and 3.4.16 map `SDLCompatible` as an Xbox pad and give `Generic` no gamepad
    // mapping, so `SDLCompatible` leads.
    guard let automatic = automaticOrder.first(where: fits) else {
      throw .virtualProfileUnavailable
    }
    return Selection(
      profileID: automatic,
      source: override.map(Selection.Source.automaticAfterRejecting) ?? .automatic
    )
  }

  /// Whether `slots` carry every control in `required`.
  ///
  /// A trigger button fits the analog trigger slot, published at `0` or `65535` when the trigger is
  /// digital-only; a controller declaring both shares that one slot, because the report encoder
  /// merges them.
  static func represents(_ required: Set<Control>, in slots: Set<Control>) -> Bool {
    required.allSatisfy { control in
      switch control {
      case .leftTrigger: return slots.contains(control) || slots.contains(.leftTrigger)
      case .rightTrigger: return slots.contains(control) || slots.contains(.rightTrigger)
      default: return slots.contains(control)
      }
    }
  }
}
