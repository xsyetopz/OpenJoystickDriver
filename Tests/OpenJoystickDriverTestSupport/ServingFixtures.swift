@testable package import OpenJoystickDriverKit

/// One controller situation with the answers every caller of the serving policy must give.
package struct ServingFixture: Sendable {
  package let name: String
  package let observation: ControllerOwnershipObservation
  package let server: ControllerServer
  package let source: DeviceDiscoverySource
  package let accessRoute: ControllerAccessRoute
  package let gameControllerSupported: Bool
  package let outputEnabled: Bool
  package let override: VirtualHIDProfileID?
  /// The route the policy must decide.
  package let route: ServingRoute
  /// Whether the user can choose who serves the controller.
  package let offersServerChoice: Bool

  package var input: ServingInput {
    ServingInput(
      observation: observation,
      server: server,
      accessRoute: accessRoute,
      gameControllerSupported: gameControllerSupported,
      outputEnabled: outputEnabled,
      controls: Control.xboxLayout,
      override: override
    )
  }

  /// The controller as the service describes it.
  package var device: ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: name,
      vendorID: 0x3537,
      productID: 0x100B,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: source,
      physicalOwnership: observation,
      gameControllerSupported: gameControllerSupported,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: server,
      recordAccessRoute: accessRoute,
      capabilities: ControllerCapabilities(controls: Control.xboxLayout),
      sessionToken: .fixture("serving-fixture")
    )
  }

  private init(
    _ name: String,
    _ observation: ControllerOwnershipObservation,
    _ server: ControllerServer,
    source: DeviceDiscoverySource = .hid,
    accessRoute: ControllerAccessRoute = .system,
    gameControllerSupported: Bool = false,
    outputEnabled: Bool = true,
    override: VirtualHIDProfileID? = nil,
    route: ServingRoute,
    offersServerChoice: Bool
  ) {
    self.name = name
    self.observation = observation
    self.server = server
    self.source = source
    self.accessRoute = accessRoute
    self.gameControllerSupported = gameControllerSupported
    self.outputEnabled = outputEnabled
    self.override = override
    self.route = route
    self.offersServerChoice = offersServerChoice
  }

  /// The fixture set the four callers are compared over.
  package static let all: [Self] = [
    Self(
      "native gamepad",
      .systemGamepad,
      .system,
      route: .nativePassThrough(.none),
      offersServerChoice: true
    ),
    Self(
      "native HID",
      .systemHIDVisible,
      .system,
      route: .nativePassThrough(.none),
      offersServerChoice: false
    ),
    Self(
      "native claimed by OJD",
      .systemGamepad,
      .ojd,
      route: .virtualHID(.sdlCompatible),
      offersServerChoice: true
    ),
    Self(
      "seized HID",
      .exclusiveHID,
      .system,
      route: .virtualHID(.sdlCompatible),
      offersServerChoice: false
    ),
    Self(
      "native pad GameController leaves unlisted",
      .exclusiveHID,
      .system,
      gameControllerSupported: true,
      route: .virtualHID(.sdlCompatible),
      offersServerChoice: true
    ),
    Self(
      "seized HID with override",
      .exclusiveHID,
      .system,
      override: .generic,
      route: .virtualHID(.generic),
      offersServerChoice: false
    ),
    Self(
      "raw USB claimed by OJD",
      .exclusiveRawUSB,
      .ojd,
      source: .rawUSB,
      accessRoute: .rawAccess,
      route: .virtualHID(.sdlCompatible),
      offersServerChoice: false
    ),
    Self(
      "extension owned",
      .extensionOwnedUSB,
      .system,
      source: .rawUSB,
      accessRoute: .extensionOwned,
      route: .extensionOwned,
      offersServerChoice: false
    ),
    Self(
      "upstream virtual",
      .upstreamVirtualDevice,
      .system,
      route: .outputDisabled(.upstreamVirtualDevice),
      offersServerChoice: false
    ),
    Self(
      "output off",
      .exclusiveHID,
      .system,
      outputEnabled: false,
      route: .outputDisabled(.userDisabled),
      offersServerChoice: false
    ),
  ]
}
