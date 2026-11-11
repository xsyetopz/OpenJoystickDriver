import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI
@testable import OpenJoystickDriverPresentation
@testable import OpenJoystickDriverService

struct ServingPolicyCallersTests {
  /// The service reports why nothing publishes from the route the policy decided, and publishes
  /// for exactly the routes that publish.
  @Test(arguments: ServingFixture.all)
  func theServiceReportsTheRouteThePolicyDecided(_ fixture: ServingFixture) {
    let route = ServingPolicy.route(
      for: fixture.device,
      outputEnabled: fixture.outputEnabled,
      override: fixture.override
    )
    #expect(route == fixture.route, "\(fixture.name)")
    let reason = ApplicationServiceServer.notPublishedReason(
      of: route,
      observation: fixture.observation
    )
    #expect((reason == nil) == route.publishesVirtualDevice, "\(fixture.name)")
  }

  /// The reason each situation gives for publishing nothing; nil for the routes that publish a
  /// persona, which include the extension-owned route.
  private static let expectedReasons:
    [String: ApplicationServicePublicationStatus.NotPublishedReason?] = [
      "native gamepad": .systemGamepad,
      "native HID": .nativeHIDPassThrough,
      "native claimed by OJD": nil,
      "seized HID": nil,
      "seized HID with override": nil,
      "raw USB claimed by OJD": nil,
      "extension owned": nil,
      "upstream virtual": .upstreamVirtualDevice,
      "output off": .outputDisabled,
    ]

  @Test(arguments: ServingFixture.all)
  func theServiceNamesTheReasonEachRouteGives(_ fixture: ServingFixture) throws {
    let expected = try #require(Self.expectedReasons[fixture.name], "\(fixture.name)")
    let reason = ApplicationServiceServer.notPublishedReason(
      of: fixture.route,
      observation: fixture.observation
    )
    #expect(reason == expected, "\(fixture.name)")
  }

  @Test
  func everyFixtureHasAnExpectedReason() {
    #expect(Set(ServingFixture.all.map(\.name)) == Set(Self.expectedReasons.keys))
  }

  /// A device whose route publishes, with the session and the controls varied.
  private static func device(
    session: ControllerSessionState,
    controls: Set<Control>
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "pad",
      vendorID: 0x3537,
      productID: 0x100B,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .hid,
      physicalOwnership: .exclusiveHID,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system,
      capabilities: ControllerCapabilities(controls: controls),
      sessionState: session,
      sessionToken: .fixture("reason-fixture")
    )
  }

  /// Runs `body` against a profile-override server and awaits its teardown, also when `body`
  /// throws.
  @MainActor
  private static func withServer(
    _ identifiers: [LogicalControllerID],
    outputEnabled: Bool,
    _ body: (ProfileOverrideServerFixture) async throws -> Void
  ) async throws {
    let server = await VirtualOutputTests().profileOverrideServer(
      identifiers,
      outputEnabled: outputEnabled
    )
    do { try await body(server) } catch {
      await server.tearDown()
      throw error
    }
    await server.tearDown()
  }

  @MainActor
  @Test
  func theServiceReportsTheReasonTheSessionAndTheProfileGive() async throws {
    let published = LogicalControllerID(vendorID: 0x3537, productID: 0x100B)
    try await Self.withServer([published], outputEnabled: true) { server in
      // A controller the dispatcher has not published, so the service decides the reason itself.
      let id = LogicalControllerID(vendorID: 0x3537, productID: 0x2222)

      let suspended = Self.device(session: .suspended, controls: Control.xboxLayout)
      let described = await server.server.describingVirtualHIDProfiles([(id, suspended)])
      #expect(described.first?.publication?.reason == .sessionSuspended)

      // The extension owns the USB link and OJD still publishes the persona, so the controller
      // waits for input like any other.
      let extensionOwned = try #require(ServingFixture.all.first { $0.name == "extension owned" })
      #expect(
        await server.server.describingVirtualHIDProfiles([(id, extensionOwned.device)]).first?
          .publication?.reason == .noInputYet
      )

      let active = Self.device(session: .active, controls: Control.xboxLayout)
      let automatic = server.server.automaticUserSpaceDispatcher()
      #expect(
        ApplicationServiceServer.publication(
          of: active,
          identifier: id,
          automatic: automatic,
          unavailable: true
        ).reason == .noVirtualProfile
      )
      #expect(
        ApplicationServiceServer.publication(
          of: active,
          identifier: id,
          automatic: automatic,
          unavailable: false
        ).reason == .noInputYet
      )
      #expect(
        ApplicationServiceServer.publication(
          of: active,
          identifier: id,
          automatic: nil,
          unavailable: false
        ).reason == .outputDisabled
      )
    }
  }

  /// What one caller says about a controller: the persona it shows and whether it offers the
  /// server choice.
  private struct Answer: Equatable {
    let persona: String?
    let offersServerChoice: Bool
  }

  /// Runs one fixture through the callers' real entry points and compares their answers: the
  /// service's description (which the endpoint's controller stream also serves), the CLI's
  /// `virtual show` report and claim check, and the GUI's persona and ownership picker.
  @MainActor
  @Test(arguments: ServingFixture.all)
  func theServiceDescriptionTheWatchStreamServesTheCLIAndTheGUIAnswerWhatThePolicyDecided(
    _ fixture: ServingFixture
  ) async throws {
    let id = LogicalControllerID(vendorID: 0x3537, productID: 0x100B)
    try await Self.withServer([id], outputEnabled: fixture.outputEnabled) { server in
      if let override = fixture.override {
        try server.store.set(override, vendorID: 0x3537, productID: 0x100B)
      }

      // Service and endpoint: the description the service builds for its status and watch stream.
      let described = try #require(
        await server.server.describingVirtualHIDProfiles([(id, fixture.device)]).first
      )
      let service = Answer(
        persona: described.virtualHIDProfile?.profile?.rawValue,
        offersServerChoice: ServingPolicy.offersServerChoice(ServingInput(described))
      )
      // CLI: the `virtual show` report and the `controller claim` check.
      let cliAccepts =
        (try? ControllerServerChange.checkSupported(
          described,
          server: fixture.server,
          accessRoute: fixture.accessRoute
        )) != nil
      let cli = Answer(
        persona: try VirtualShowReport.Controller(described).profile,
        offersServerChoice: cliAccepts
      )
      // GUI: the persona it shows and whether it shows the picker.
      let gui = Answer(
        persona: described.publishedVirtualProfile.flatMap { identity in
          VirtualHIDProfileID.allCases.first { $0.identity == identity }?.rawValue
        },
        offersServerChoice: ControllerServerPicker.isShown(for: described)
      )

      let expected: String?
      switch fixture.route {
      case .virtualHID(let persona): expected = persona.rawValue
      case .extensionOwned: expected = VirtualHIDProfileID.sdlCompatible.rawValue
      case .nativePassThrough, .outputDisabled: expected = nil
      }
      let answer = Answer(persona: expected, offersServerChoice: fixture.offersServerChoice)
      #expect(service == answer, "\(fixture.name) service")
      #expect(cli == answer, "\(fixture.name) cli")
      #expect(gui == answer, "\(fixture.name) gui")
    }
  }
}
