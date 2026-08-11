import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

@Suite(.serialized) struct StatusTests {
  @Test func unresolvedPermissionStatesNeedUserAction() {
    #expect(RuntimePresentation.permissionLabel(.unknown) == "Needs attention")
    #expect(RuntimePresentation.permissionLabel(.denied) == "Needs attention")
  }

  @Test func translatesStatusAndUsesOpaqueDeviceSelector() async throws {
    let device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      parser: "GIP",
      connection: "USB",
      serialNumber: nil,
      runtimeIdentifier: "session-device-7"
    )
    let input = DeviceInputState(vendorID: device.vendorID, productID: device.productID)
    let gateway = GatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputMonitoring: "granted",
        accessibility: "granted",
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready",
        compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
      ),
      inputState: input
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.refresh()
    let statusState = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = statusState else {
      Issue.record("Expected an available status")
      return
    }
    #expect(status.readiness == .ready)
    #expect(status.deviceCountLabel == "1 controller connected")
    #expect(status.compatibilityLabel == "SDL2/3")
    #expect(RuntimePresentation.sourceLabel(.button(.south)) == "A / Cross")
    #expect(
      RuntimePresentation.destinationLabel(.keyboard(key: .a, modifiers: [.command, .shift]))
        == "Command + Shift + A"
    )

    let selector = RuntimeDeviceSelector(device: device)
    await viewModel.readInputState(for: selector)
    let captureState = await MainActor.run { viewModel.inputCaptureState }
    guard case .received(let capturedSelector, let capturedState) = captureState else {
      Issue.record("Expected a captured input state")
      return
    }
    #expect(capturedSelector == selector)
    #expect(capturedState == input)
    #expect(await gateway.lastInputSelector == selector)
  }

  @Test func statusReadinessWaitsForPostEventAccess() async {
    let device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      parser: "GIP",
      connection: "USB",
      serialNumber: nil,
      runtimeIdentifier: "session-device-8"
    )
    let profile = makeProfile(name: "Mapped")
    let activeProfile = ApplicationServiceRemappingActiveProfilePayload(
      vendorID: profile.device.vendorID,
      productID: profile.device.productID,
      profileID: profile.id,
      profileName: profile.name,
      applicationScope: profile.applicationScope
    )
    let gateway = GatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputMonitoring: "granted",
        accessibility: "granted",
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready",
        compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
      ),
      snapshotPayload: snapshot(
        profiles: [profile],
        activeProfiles: [activeProfile],
        postEventAccess: .notAuthorized
      )
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.refresh()

    let statusState = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = statusState else {
      Issue.record("Expected an available status")
      return
    }
    #expect(status.postEventAccess == .notAuthorized)
    #expect(status.requiresPostEventAccess == true)
    #expect(status.postEventAccessLabel == "Needs attention")
    #expect(status.readiness == .needsAttention)
  }

  @Test func statusReadinessIgnoresPostEventAccessWithoutActiveMappings() async {
    let device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      parser: "GIP",
      connection: "USB",
      serialNumber: nil,
      runtimeIdentifier: "session-device-9"
    )
    let gateway = GatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputMonitoring: "granted",
        accessibility: "granted",
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready",
        compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
      ),
      snapshotPayload: snapshot(profiles: [], postEventAccess: .notAuthorized)
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.refresh()

    let statusState = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = statusState else {
      Issue.record("Expected an available status")
      return
    }
    #expect(status.postEventAccess == .notAuthorized)
    #expect(status.requiresPostEventAccess == false)
    #expect(status.readiness == .ready)
  }

  @Test func statusReadinessRemainsUnknownBeforeRemappingSnapshot() {
    let payload = ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: [],
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: "ready",
      compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
    )
    let presentation = RuntimeStatusPresentation(payload: payload, postEventAccess: .granted)

    #expect(presentation.requiresPostEventAccess == nil)
    #expect(presentation.readiness == .needsAttention)
  }
}
