#if canImport(SwiftUI)

  import OpenJoystickDriverKit
  import OpenJoystickDriverTestSupport
  import SwiftUI
  import Testing

  @testable import OpenJoystickDriverPresentation

  @Suite
  @MainActor
  struct ProfileEditorActionsTests {
    private static func view(
      profile: RemappingProfile,
      draftProfile: RemappingProfile? = nil,
      isActive: Bool = false,
      gateway: GatewayStub
    ) -> ProfileEditorView {
      let runtime = RuntimeViewModel(gateway: gateway)
      let editor = ProfileEditorViewModel(profile: draftProfile ?? profile)
      return ProfileEditorView(
        profile: profile,
        capabilities: .unknown,
        editor: editor,
        viewModel: runtime,
        library: ProfileLibraryModel(runtime: runtime),
        isActive: isActive,
        isEditingBlocked: false,
        selectedSection: .constant(.assignments),
        onEditingStateChanged: { _ in },
        onMutationStarted: { _ in true },
        onMutationResult: { _ in }
      )
    }

    @Test
    func confirmedActivationReachesGatewayWithAllowance() async {
      let profile = makeProfile()
      let gateway = GatewayStub(snapshotPayload: snapshot(profiles: [profile]))
      let view = Self.view(profile: profile, gateway: gateway)

      view.activateProfile(allowEmpty: true)
      await waitUntil("the activation reaches the gateway") {
        await gateway.activationAllowEmpty == [true]
      }

      #expect(await gateway.activationAllowEmpty == [true])
    }

    @Test
    func activationWithoutConfirmationAsksForNoAllowance() async {
      let profile = makeProfile()
      let gateway = GatewayStub(snapshotPayload: snapshot(profiles: [profile]))
      let view = Self.view(profile: profile, gateway: gateway)

      view.activateProfile(allowEmpty: false)
      await waitUntil("the activation reaches the gateway") {
        await gateway.activationAllowEmpty == [false]
      }

      #expect(await gateway.activationAllowEmpty == [false])
    }

    @Test
    func joyConSessionOfProfileDecidesWhetherDeactivationIsOffered() {
      let pair = RemappingProfile(
        name: "Pair",
        device: RemappingDeviceScope(vendorID: 0x057E, productID: 0x2006),
        applicationScope: .global,
        joyConPair: RemappingJoyConPairSettings(gyroSelection: .left),
        bindings: []
      )
      let ordinary = RemappingProfile(
        id: pair.id,
        name: "Pair",
        device: pair.device,
        applicationScope: .global,
        bindings: []
      )
      let gateway = GatewayStub()

      let paired = Self.view(
        profile: pair,
        draftProfile: ordinary,
        isActive: true,
        gateway: gateway
      )
      let unpaired = Self.view(profile: ordinary, isActive: true, gateway: gateway)

      #expect(!paired.menuActions.contains(.deactivateAll))
      #expect(unpaired.menuActions.contains(.deactivateAll))
    }

    @Test
    func virtualOutputOtherThanDisabledReturnsPhysicalInputToShared() {
      let exclusive = RemappingOutputPolicy(virtualGamepad: .disabled, physicalInput: .exclusive)

      for virtual in [RemappingVirtualGamepadPolicy.mapped, .passthrough] {
        #expect(
          ProfileOutputPolicyView.policy(selecting: virtual, from: exclusive)
            == RemappingOutputPolicy(virtualGamepad: virtual, physicalInput: .shared)
        )
      }
    }

    @Test
    func disablingVirtualOutputKeepsPhysicalInputChoice() {
      let exclusive = RemappingOutputPolicy(virtualGamepad: .disabled, physicalInput: .exclusive)

      #expect(
        ProfileOutputPolicyView.policy(selecting: .disabled, from: exclusive) == exclusive
      )
    }
  }

#endif
