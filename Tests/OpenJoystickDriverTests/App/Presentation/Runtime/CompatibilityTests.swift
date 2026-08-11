import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

@Suite(.serialized) struct CompatibilityTests {
  @Test func rejectedCompatibilityIdentityDoesNotPublishRequestedValue() async {
    let gateway = GatewayStub(setIdentityResult: false)
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.setCompatibilityIdentity(.appleGameController)

    let state = await MainActor.run { viewModel.compatibilityState }
    guard case .error(let message) = state else {
      Issue.record("Expected a rejected identity to produce an error")
      return
    }
    #expect(message == "The selected controller output could not be enabled.")
    #expect(await MainActor.run { viewModel.compatibilityError } == message)
    #expect(await gateway.selectedIdentity == .sdl2_3)
  }

  @Test func resettingCompatibilityIdentityUsesTheScopedMutation() async {
    let gateway = GatewayStub()
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.resetCompatibilityIdentity()

    #expect(await gateway.selectedIdentity == .sdl2_3)
    #expect(await gateway.setIdentityCallCount == 1)
  }

  @Test func compatibilitySuccessDoesNotInheritAnUnrelatedRuntimeError() async {
    let gateway = GatewayStub(statusShouldFail: true)
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.refresh()

    let state = await MainActor.run { (viewModel.compatibilityState, viewModel.compatibilityError) }
    guard case .available = state.0 else {
      Issue.record("Expected compatibility identity loading to succeed")
      return
    }
    #expect(state.1 == nil)
    #expect(await MainActor.run { viewModel.lastError } != nil)
  }

  @Test func newerCompatibilitySelectionWinsOverAnOlderIdentityRead() async {
    let gateway = GatewayStub(compatibilityReadDelayNanoseconds: 100_000_000)
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    let read = Task { @MainActor in await viewModel.loadCompatibilityIdentity() }
    try? await Task.sleep(nanoseconds: 10_000_000)

    await viewModel.setCompatibilityIdentity(.appleGameController)
    await read.value

    let state = await MainActor.run { viewModel.compatibilityState }
    guard case .available(let identity) = state else {
      Issue.record("Expected the newer compatibility selection to remain authoritative")
      return
    }
    #expect(identity == .appleGameController)
  }

  @Test func compatibilitySelectionUpdatesTheStatusSummary() async {
    let gateway = GatewayStub()
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.refresh()
    await viewModel.setCompatibilityIdentity(.appleGameController)

    let state = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = state else {
      Issue.record("Expected the status summary to remain available")
      return
    }
    #expect(status.compatibilityIdentity == .appleGameController)
    #expect(status.compatibilityLabel == "Apple GameController")
  }
}
