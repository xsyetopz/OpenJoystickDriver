/// Why OJD serves a controller no output.
public enum OutputDisabledReason: String, Codable, CaseIterable, Equatable, Sendable {
  /// The user turned virtual output off.
  case userDisabled = "UserDisabled"
  /// Another virtual device already stands for the controller, so a second one would duplicate it.
  case upstreamVirtualDevice = "UpstreamVirtualDevice"
  /// No persona can represent the controller's primary controls.
  case noVirtualProfile = "NoVirtualProfile"
}

/// The one way OJD serves a controller.
///
/// Exactly one route holds for each controller.
public enum ServingRoute: Equatable, Sendable {
  /// The system serves the controller and OJD publishes nothing. The allowance is what OJD may
  /// still drive on the physical controller: the motors and lighting the system leaves undone.
  case nativePassThrough(PhysicalControllerOutputCapabilities)
  /// OJD publishes a virtual HID gamepad with this persona.
  case virtualHID(VirtualHIDProfileID)
  /// OJD's signed USB extension claims the controller and serves it.
  case extensionOwned
  /// OJD serves no output for the controller.
  case outputDisabled(OutputDisabledReason)
}

/// Everything the serving policy reads about one controller.
///
/// The serving-routes spec names four inputs; each maps to fields here.
///
/// - The record: ``server`` (who the record says serves the model, after the bundled, package and
///   user layers) and ``accessRoute`` (how the record reaches the controller: the signed USB
///   extension, raw USB, or the system HID stack), plus the ``controls`` the record's parser
///   declares.
/// - The link: ``observation``, how the physical input path is owned or observed right now.
/// - The user setting: ``outputEnabled`` (virtual output on or off) and ``override`` (the persona
///   the user chose). The `server` setting the user changes with `controller claim` and
///   `controller release` is written to the record layers, so it reaches the policy as ``server``.
/// - The per-app allowance: no mechanism exists that grants or withholds output per application,
///   so the policy has no such input. ``allowance`` is the controller-side allowance only: what OJD
///   may still drive on a controller the system serves.
public struct ServingInput: Equatable, Sendable {
  /// How the physical input path is owned or observed.
  public var observation: ControllerOwnershipObservation
  /// Who the controller's record says serves the model.
  public var server: ControllerServer
  /// How the controller's record reaches it.
  public var accessRoute: ControllerAccessRoute
  /// Whether macOS can serve the controller as a native gamepad when OJD leaves it alone.
  public var gameControllerSupported: Bool
  /// Whether virtual output is on.
  public var outputEnabled: Bool
  /// The normalized controls the controller declares.
  public var controls: Set<Control>
  /// The persona the user chose for this controller, if any.
  public var override: VirtualHIDProfileID?
  /// What OJD may drive on the physical controller when the system serves it.
  public var allowance: PhysicalControllerOutputCapabilities

  /// Creates the input from its values.
  public init(
    observation: ControllerOwnershipObservation,
    server: ControllerServer = .system,
    accessRoute: ControllerAccessRoute = .system,
    gameControllerSupported: Bool = false,
    outputEnabled: Bool = true,
    controls: Set<Control> = [],
    override: VirtualHIDProfileID? = nil,
    allowance: PhysicalControllerOutputCapabilities = .none
  ) {
    self.observation = observation
    self.server = server
    self.accessRoute = accessRoute
    self.gameControllerSupported = gameControllerSupported
    self.outputEnabled = outputEnabled
    self.controls = controls
    self.override = override
    self.allowance = allowance
  }

  /// The inputs one controller description carries. `outputEnabled` defaults to what the
  /// description reports: the service marks a controller it publishes nothing for because virtual
  /// output is off with the publication reason `outputDisabled`.
  public init(
    _ device: ApplicationServiceDeviceDescription,
    outputEnabled: Bool? = nil,
    override: VirtualHIDProfileID? = nil
  ) {
    self.init(
      observation: device.physicalOwnership,
      server: device.recordServer,
      accessRoute: device.recordAccessRoute,
      gameControllerSupported: device.gameControllerSupported,
      outputEnabled: outputEnabled ?? (device.publication?.reason != .outputDisabled),
      controls: device.capabilities.controls,
      override: override,
      allowance: device.physicalOutputCapabilities
    )
  }

  /// The inputs for the question "which persona does OJD publish if it serves this controller".
  ///
  /// The inputs assume that OJD serves the controller: the server is ``ControllerServer/ojd``, and
  /// an observation that the system or an upstream virtual device serves it is reset to unknown.
  ///
  /// A live toggle of the `server` setting changes the answer to "who serves", never the persona.
  public init(
    serving device: ApplicationServiceDeviceDescription,
    override: VirtualHIDProfileID? = nil
  ) {
    var input = Self(device, override: override)
    input.server = .ojd
    if input.observation.isServedBySystem || input.observation == .upstreamVirtualDevice {
      input.observation = .unknown
    }
    self = input
  }
}

/// The policy's answer: the route, and the persona selection behind it when the route publishes.
public struct ServingDecision: Equatable, Sendable {
  /// How OJD serves the controller.
  public let route: ServingRoute
  /// The persona and how it was chosen; nil for a route that publishes nothing.
  public let selection: VirtualHIDProfileSelector.Selection?

  /// Creates a decision from a route and the selection behind it.
  init(route: ServingRoute, selection: VirtualHIDProfileSelector.Selection? = nil) {
    self.route = route
    self.selection = selection
  }
}

/// The single pure decision of how OJD serves a controller.
///
/// The service, the CLI, the GUI and the endpoint ask it and decide nothing themselves. It is the
/// only caller of ``VirtualHIDProfileSelector``.
public enum ServingPolicy {
  /// The route for `input`.
  ///
  /// Equal inputs give equal routes.
  public static func route(_ input: ServingInput) -> ServingRoute { decision(input).route }

  /// The route for `input` with the persona selection behind it.
  public static func decision(_ input: ServingInput) -> ServingDecision {
    if !input.outputEnabled { return ServingDecision(route: .outputDisabled(.userDisabled)) }
    if input.observation == .upstreamVirtualDevice {
      return ServingDecision(route: .outputDisabled(.upstreamVirtualDevice))
    }
    if isHeldByAppleDriver(input) {
      return ServingDecision(route: .nativePassThrough(input.allowance))
    }
    // A record that gives a natively served model to OJD turns passthrough into a virtual gamepad.
    if input.observation.isServedBySystem, input.server == .system, input.accessRoute == .system {
      return ServingDecision(route: .nativePassThrough(input.allowance))
    }
    guard
      let selection = try? VirtualHIDProfileSelector.select(
        controls: input.controls,
        override: input.override
      )
    else { return ServingDecision(route: .outputDisabled(.noVirtualProfile)) }
    if input.accessRoute == .extensionOwned || input.observation == .extensionOwnedUSB {
      return ServingDecision(route: .extensionOwned, selection: selection)
    }
    return ServingDecision(route: .virtualHID(selection.profileID), selection: selection)
  }

  /// The route for one controller description.
  public static func route(
    for device: ApplicationServiceDeviceDescription,
    outputEnabled: Bool? = nil,
    override: VirtualHIDProfileID? = nil
  ) -> ServingRoute {
    route(ServingInput(device, outputEnabled: outputEnabled, override: override))
  }

  /// The persona OJD publishes for `device` when it serves the controller; nil when no persona
  /// can represent the controller.
  public static func publishedPersona(
    for device: ApplicationServiceDeviceDescription,
    override: VirtualHIDProfileID? = nil
  ) -> VirtualHIDProfileSelector.Selection? {
    decision(ServingInput(serving: device, override: override)).selection
  }

  /// Whether Apple's driver holds the controller.
  ///
  /// The system serves it natively although OJD's record reaches it through the extension.
  /// Claiming it means activating the extension.
  public static func isHeldByAppleDriver(_ input: ServingInput) -> Bool {
    input.accessRoute == .extensionOwned && input.observation == .systemGamepad
  }

  /// Whether the user can choose between the system and OJD serving a controller: the system
  /// serves it natively or can, or its record already gives it to OJD, and its record does not
  /// reach it through raw USB or the extension, which always belong to OJD.
  public static func offersServerChoice(_ input: ServingInput) -> Bool {
    input.accessRoute == .system
      && (input.observation == .systemGamepad || input.gameControllerSupported
        || input.server == .ojd)
  }
}

extension ApplicationServiceDeviceDescription {
  /// Whether Apple's driver holds this controller; see ``ServingPolicy/isHeldByAppleDriver(_:)``.
  public var isHeldByAppleDriver: Bool { ServingPolicy.isHeldByAppleDriver(ServingInput(self)) }

  /// The serving decision for this controller, with the persona override it reports.
  ///
  /// Every caller that shows or checks a route or persona reads it here instead of deciding on
  /// its own.
  public var servingDecision: ServingDecision {
    ServingPolicy.decision(ServingInput(self, override: virtualHIDProfile?.override))
  }
}

extension ServingRoute {
  /// The name of the route in the serving-routes spec, such as `VirtualHID`.
  ///
  /// The CLI prints it and the schema lists it.
  public var id: String {
    switch self {
    case .nativePassThrough: "NativePassThrough"
    case .virtualHID: "VirtualHID"
    case .extensionOwned: "ExtensionOwned"
    case .outputDisabled: "OutputDisabled"
    }
  }

  /// Why the route publishes nothing; nil for a route that serves.
  public var disabledReason: OutputDisabledReason? {
    if case .outputDisabled(let reason) = self { return reason }
    return nil
  }

  /// Whether a virtual device may publish for the controller under this route.
  public var publishesVirtualDevice: Bool {
    switch self {
    case .virtualHID, .extensionOwned: true
    case .nativePassThrough, .outputDisabled: false
    }
  }
}
