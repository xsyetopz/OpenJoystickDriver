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

  @Test func detectedTransitionCapturesNewTouchSurfaceButNotHeldContactMovement() {
    let previous = DeviceInputState(vendorID: 1, productID: 2)
    var touched = previous
    touched.touchSamples = [touchSample(surface: .right, x: 10)]
    var moved = touched
    moved.touchSamples = [touchSample(surface: .right, x: 50)]

    #expect(
      RuntimePresentation.detectedTransition(from: previous, to: touched)
        == .touchContact(.right)
    )
    #expect(RuntimePresentation.detectedTransition(from: touched, to: moved) == nil)
  }

  @Test func detectedSourceIncludesNamedExtraAndDigitalControllerAliases() {
    var state = DeviceInputState(vendorID: 0x1234, productID: 0x5678)
    state.pressedButtons = ["left_function"]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.leftFunction))

    state.pressedButtons = ["right_function"]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.rightFunction))

    state.pressedButtons = ["left_paddle"]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.leftPaddle))

    state.pressedButtons = ["right_paddle"]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.rightPaddle))

    state.pressedButtons = ["left_sl"]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.leftSL))

    state.pressedButtons = ["left_sr"]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.leftSR))

    state.pressedButtons = ["right_sl"]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.rightSL))

    state.pressedButtons = ["right_sr"]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.rightSR))

    state.pressedButtons = ["share"]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.share))

    state.pressedButtons = ["l2Digital"]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.leftTriggerClick))

    state.pressedButtons = ["r2Digital"]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.rightTriggerClick))
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
    current.pressedButtons = ["mute"]
    #expect(RuntimePresentation.detectedTransition(from: previous, to: current) == .button(.mute))

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

  private func touchSample(surface: ControllerTouchSurface, x: Int32) -> ControllerTouchSample {
    ControllerTouchSample(
      reportTimestamp: ControllerSampleTimestamp(
        rawCounter: 0,
        elapsedNanoseconds: 0,
        tickNanosecondsNumerator: nil,
        tickNanosecondsDenominator: nil,
        sequenceIndex: 0,
        basis: .hostEstimate
      ),
      rawTouchCounter: nil,
      historyIndex: 0,
      width: 100,
      height: 100,
      contacts: [ControllerTouchContact(id: 0, isActive: true, x: x, y: 10)],
      surface: surface
    )
  }
}
