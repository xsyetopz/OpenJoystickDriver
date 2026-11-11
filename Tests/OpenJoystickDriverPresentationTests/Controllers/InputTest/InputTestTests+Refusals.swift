import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

/// What the user sees when an output test is not sent: a failed state with the reason, and a
/// player indicator that applies when it is chosen.
extension InputTestTests {
  private static let allOutputs = PhysicalControllerOutputCapabilities(
    rumbleMotors: [.lowFrequency],
    lightingFeatures: [.playerIndicator, .programmableColor, .programmableBrightness]
  )

  private static let notConnectedText = OJDLocalized.string("ui.inputTest.outputNotConnected")
  private static let unsupportedText = OJDLocalized.string("ui.inputTest.outputUnsupported")

  /// Selects a controller with `capabilities`, optionally already disconnected.
  @MainActor
  private func model(
    capabilities: PhysicalControllerOutputCapabilities,
    connected: Bool,
    gateway: InputTestGatewayStub
  ) -> InputTestViewModel {
    let model = InputTestViewModel(gateway: gateway)
    model.selectDevice(makeInputTestDevice(capabilities: capabilities))
    if !connected { model.reconcileConnectedDevices([]) }
    return model
  }

  @Test
  @MainActor
  func rumbleWithoutAConnectedControllerFailsWithTheReason() async {
    let gateway = InputTestGatewayStub()
    let model = model(capabilities: Self.allOutputs, connected: false, gateway: gateway)
    model.testRumble()
    #expect(model.outputState == .failed(.rumble))
    #expect(model.outputError == Self.notConnectedText)
    #expect(await gateway.counts().rumble == 0)
  }

  @Test
  @MainActor
  func rumbleOnAControllerWithoutMotorsFailsWithTheReason() async {
    let gateway = InputTestGatewayStub()
    let model = model(capabilities: .none, connected: true, gateway: gateway)
    model.testRumble()
    #expect(model.outputState == .failed(.rumble))
    #expect(model.outputError == Self.unsupportedText)
    #expect(await gateway.counts().rumble == 0)
  }

  @Test
  @MainActor
  func playerIndicatorWithoutAConnectedControllerFailsWithTheReason() async {
    let gateway = InputTestGatewayStub()
    let model = model(capabilities: Self.allOutputs, connected: false, gateway: gateway)
    model.choosePlayerIndicator(.player2)
    #expect(model.playerIndicator == .player2)
    #expect(model.outputState == .failed(.playerIndicator))
    #expect(model.outputError == Self.notConnectedText)
    #expect(await gateway.counts().player == 0)
  }

  @Test
  @MainActor
  func playerIndicatorOnAControllerWithoutOneFailsWithTheReason() async {
    let gateway = InputTestGatewayStub()
    let model = model(capabilities: .none, connected: true, gateway: gateway)
    model.applyPlayerIndicator()
    #expect(model.outputState == .failed(.playerIndicator))
    #expect(model.outputError == Self.unsupportedText)
    #expect(await gateway.counts().player == 0)
  }

  @Test
  @MainActor
  func colorWithoutAConnectedControllerFailsWithTheReason() async {
    let gateway = InputTestGatewayStub()
    let model = model(capabilities: Self.allOutputs, connected: false, gateway: gateway)
    model.applyColor()
    #expect(model.outputState == .failed(.color))
    #expect(model.outputError == Self.notConnectedText)
    #expect(await gateway.counts().color == 0)
  }

  @Test
  @MainActor
  func colorOnAControllerWithoutOneFailsWithTheReason() async {
    let gateway = InputTestGatewayStub()
    let model = model(capabilities: .none, connected: true, gateway: gateway)
    model.applyColor()
    #expect(model.outputState == .failed(.color))
    #expect(model.outputError == Self.unsupportedText)
    #expect(await gateway.counts().color == 0)
  }

  @Test
  @MainActor
  func brightnessWithoutAConnectedControllerFailsWithTheReason() async {
    let gateway = InputTestGatewayStub()
    let model = model(capabilities: Self.allOutputs, connected: false, gateway: gateway)
    model.applyBrightness()
    #expect(model.outputState == .failed(.brightness))
    #expect(model.outputError == Self.notConnectedText)
    #expect(await gateway.counts().brightness == 0)
  }

  @Test
  @MainActor
  func brightnessOnAControllerWithoutItFailsWithTheReason() async {
    let gateway = InputTestGatewayStub()
    let model = model(capabilities: .none, connected: true, gateway: gateway)
    model.applyBrightness()
    #expect(model.outputState == .failed(.brightness))
    #expect(model.outputError == Self.unsupportedText)
    #expect(await gateway.counts().brightness == 0)
  }

  @Test
  @MainActor
  func stopIsUnavailableWhileNoRumbleRuns() {
    let model = model(
      capabilities: Self.allOutputs,
      connected: true,
      gateway: InputTestGatewayStub()
    )
    #expect(!model.canStopRumble)
    model.stopRumble()
    #expect(model.outputState == .idle)
  }

  @Test
  @MainActor
  func choosingAPlayerIndicatorAppliesItWithoutAnApplyButton() async {
    let gateway = InputTestGatewayStub()
    let model = model(capabilities: Self.allOutputs, connected: true, gateway: gateway)
    model.choosePlayerIndicator(.player4)
    await waitUntil("the indicator is sent") { await !gateway.playerCalls.isEmpty }
    #expect(await gateway.playerCalls.first?.1 == .player4)
    await waitUntil("the indicator succeeds") { model.outputState == .succeeded(.playerIndicator) }
    #expect(model.outputError == nil)
  }
}
