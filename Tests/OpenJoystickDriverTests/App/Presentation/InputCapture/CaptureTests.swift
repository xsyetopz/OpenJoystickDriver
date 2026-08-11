import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

@Suite(.serialized) struct InputCaptureTests {
  @Test func listensUntilItFindsAControllerControl() async {
    let selector = RuntimeDeviceSelector(
      vendorID: 0x1234,
      productID: 0x5678,
      runtimeIdentifier: "live"
    )
    let released = DeviceInputState(vendorID: selector.vendorID, productID: selector.productID)
    var pressed = released
    pressed.pressedButtons = ["A"]
    let gateway = GatewayStub(inputSequence: [released, pressed])
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.listenForInput(for: selector)

    let captureState = await MainActor.run { viewModel.inputCaptureState }
    guard case .detected(let capturedSelector, let capturedState, let detectedSource) = captureState
    else {
      Issue.record("Expected the next meaningful controller transition")
      return
    }
    #expect(capturedSelector == selector)
    #expect(detectedSource == .button(.south))
    #expect(RuntimePresentation.detectedSource(from: capturedState) == .button(.south))
  }

  @Test func listenIgnoresAControlHeldBeforeListening() async {
    let selector = RuntimeDeviceSelector(
      vendorID: 0x1234,
      productID: 0x5678,
      runtimeIdentifier: "live"
    )
    var held = DeviceInputState(vendorID: selector.vendorID, productID: selector.productID)
    held.pressedButtons = ["A"]
    let released = DeviceInputState(vendorID: selector.vendorID, productID: selector.productID)
    var pressedAgain = released
    pressedAgain.pressedButtons = ["A"]
    let gateway = GatewayStub(inputSequence: [held, held, released, pressedAgain])
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.listenForInput(for: selector)

    let captureState = await MainActor.run { viewModel.inputCaptureState }
    guard case .detected(_, let state, let detectedSource) = captureState else {
      Issue.record("Expected a later press after the held baseline")
      return
    }
    #expect(detectedSource == .button(.south))
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.south))
  }

  @Test func listenPublishesTheTransitionSourceWhenAnotherControlWasAlreadyHeld() async {
    let selector = RuntimeDeviceSelector(
      vendorID: 0x1234,
      productID: 0x5678,
      runtimeIdentifier: "live"
    )
    var baseline = DeviceInputState(vendorID: selector.vendorID, productID: selector.productID)
    baseline.pressedButtons = ["A"]
    var changed = baseline
    changed.pressedButtons = ["A", "B"]
    let gateway = GatewayStub(inputSequence: [baseline, changed])
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.listenForInput(for: selector)

    let captureState = await MainActor.run { viewModel.inputCaptureState }
    guard case .detected(_, _, let detectedSource) = captureState else {
      Issue.record("Expected the newly pressed control")
      return
    }
    #expect(detectedSource == .button(.east))
  }

  @Test func detectedSourceUsesCanonicalButtonDpadAndAxisOrder() {
    var state = DeviceInputState(vendorID: 0x1234, productID: 0x5678)
    state.pressedButtons = ["Circle", "A"]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.south))

    state.pressedButtons = ["D-pad Left"]
    #expect(RuntimePresentation.detectedSource(from: state) == .dpad(.left))

    state.pressedButtons = []
    state.leftStickX = -0.75
    #expect(
      RuntimePresentation.detectedSource(from: state) == .axisDirection(.leftStickX, .negative)
    )

    state.leftStickX = 0.2
    state.rightTrigger = 0.7
    #expect(
      RuntimePresentation.detectedSource(from: state) == .axisDirection(.rightTrigger, .positive)
    )

    state.rightTrigger = 0.2
    #expect(RuntimePresentation.detectedSource(from: state) == nil)
  }

  @Test func detectedSourceIncludesGenericAndDigitalControllerAliases() {
    var state = DeviceInputState(vendorID: 0x1234, productID: 0x5678)
    state.pressedButtons = ["genericButton4"]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.auxiliary4))

    state.pressedButtons = ["l2Digital"]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.auxiliary1))

    state.pressedButtons = ["r2Digital"]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.auxiliary2))
  }

  @Test func detectedSourceIgnoresReservedGuideAndHomeControls() {
    var state = DeviceInputState(vendorID: 0x1234, productID: 0x5678)
    state.pressedButtons = ["Guide"]
    #expect(RuntimePresentation.detectedSource(from: state) == nil)

    state.pressedButtons = ["Home"]
    #expect(RuntimePresentation.detectedSource(from: state) == nil)
  }

  @Test func detectedTransitionUsesCanonicalAliasesAndAxisThresholds() {
    let previous = DeviceInputState(vendorID: 0x1234, productID: 0x5678)
    var current = previous
    current.pressedButtons = ["genericButton7"]
    #expect(
      RuntimePresentation.detectedTransition(from: previous, to: current) == .button(.auxiliary7)
    )

    current.pressedButtons = []
    current.leftStickX = 0.75
    #expect(
      RuntimePresentation.detectedTransition(from: previous, to: current)
        == .axisDirection(.leftStickX, .positive)
    )

    var held = current
    held.leftStickX = 0.8
    #expect(RuntimePresentation.detectedTransition(from: current, to: held) == nil)

    held.leftStickX = -0.8
    #expect(
      RuntimePresentation.detectedTransition(from: current, to: held)
        == .axisDirection(.leftStickX, .negative)
    )
  }

  @Test func detectedTransitionIgnoresReleaseOnlyChanges() {
    var previous = DeviceInputState(vendorID: 0x1234, productID: 0x5678)
    previous.pressedButtons = ["A", "B"]
    var current = previous
    current.pressedButtons = ["B"]

    #expect(RuntimePresentation.detectedTransition(from: previous, to: current) == nil)
  }
}
