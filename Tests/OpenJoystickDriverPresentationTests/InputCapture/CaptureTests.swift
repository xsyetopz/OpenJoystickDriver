import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@Suite(.serialized)
struct InputCaptureTests {
  @Test
  func listensUntilItFindsControllerControl() async {
    let selector = ControllerReference.session(.fixture("live"))
    let released = ControllerState.neutral
    var pressed = released
    pressed.pressed = [.south]
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
    #expect(
      RuntimePresentation.detectedSource(from: capturedState) == .button(.south)
    )
  }

  @Test
  func listenIgnoresControlHeldBeforeListening() async {
    let selector = ControllerReference.session(.fixture("live"))
    var held = ControllerState.neutral
    held.pressed = [.south]
    let released = ControllerState.neutral
    var pressedAgain = released
    pressedAgain.pressed = [.south]
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

  @Test
  func listenPublishesTransitionSourceWhenAnotherControlWasAlreadyHeld() async {
    let selector = ControllerReference.session(.fixture("live"))
    var baseline = ControllerState.neutral
    baseline.pressed = [.south]
    var changed = baseline
    changed.pressed = [.south, .east]
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

  @Test
  func detectedSourceUsesCanonicalButtonDpadAndAxisOrder() {
    var state = ControllerState.neutral
    state.pressed = [.east, .south]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.south))

    state.pressed = []
    state.hat = .west
    #expect(RuntimePresentation.detectedSource(from: state) == .dpad(.left))

    state.hat = .neutral
    state.leftStick.x = BipolarValue(normalized: -0.75)
    #expect(
      RuntimePresentation.detectedSource(from: state)
        == .axisDirection(.leftStickX, .negative)
    )

    state.leftStick.x = BipolarValue(normalized: 0.2)
    state.rightTrigger = UnipolarValue(normalized: 0.7)
    #expect(
      RuntimePresentation.detectedSource(from: state)
        == .axisDirection(.rightTrigger, .positive)
    )

    state.rightTrigger = UnipolarValue(normalized: 0.2)
    #expect(RuntimePresentation.detectedSource(from: state) == nil)
  }

  @Test
  func detectedTransitionCapturesNewTouchSurfaceButNotHeldContactMovement() {
    let previous = ControllerState.neutral
    var touched = previous
    touched.touch = [touchSample(surface: .right, x: 10)]
    var moved = touched
    moved.touch = [touchSample(surface: .right, x: 50)]

    #expect(
      RuntimePresentation.detectedTransition(from: previous, to: touched)
        == .touchContact(.right)
    )
    #expect(
      RuntimePresentation.detectedTransition(from: touched, to: moved) == nil
    )
  }

  @Test
  func detectedSourceIncludesNamedExtraAndDigitalControllerAliases() {
    var state = ControllerState.neutral
    state.pressed = [.auxiliary1]
    #expect(
      RuntimePresentation.detectedSource(from: state) == .button(.auxiliary1)
    )

    state.pressed = [.auxiliary2]
    #expect(
      RuntimePresentation.detectedSource(from: state) == .button(.auxiliary2)
    )

    state.pressed = [.leftPaddle1]
    #expect(
      RuntimePresentation.detectedSource(from: state) == .button(.leftPaddle1)
    )

    state.pressed = [.rightPaddle1]
    #expect(
      RuntimePresentation.detectedSource(from: state) == .button(.rightPaddle1)
    )

    state.pressed = [.auxiliary3]
    #expect(
      RuntimePresentation.detectedSource(from: state) == .button(.auxiliary3)
    )

    state.pressed = [.auxiliary4]
    #expect(
      RuntimePresentation.detectedSource(from: state) == .button(.auxiliary4)
    )

    state.pressed = [.auxiliary5]
    #expect(
      RuntimePresentation.detectedSource(from: state) == .button(.auxiliary5)
    )

    state.pressed = [.auxiliary6]
    #expect(
      RuntimePresentation.detectedSource(from: state) == .button(.auxiliary6)
    )

    state.pressed = [.capture]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.capture))

    state.pressed = [.leftTrigger]
    #expect(
      RuntimePresentation.detectedSource(from: state)
        == .button(.leftTrigger)
    )

    state.pressed = [.rightTrigger]
    #expect(
      RuntimePresentation.detectedSource(from: state)
        == .button(.rightTrigger)
    )
  }

  @Test
  func detectedSourceIgnoresReservedGuideAndHomeControls() {
    var state = ControllerState.neutral
    state.pressed = [.guide]
    #expect(RuntimePresentation.detectedSource(from: state) == nil)

    state.pressed = [.guide]
    #expect(RuntimePresentation.detectedSource(from: state) == nil)
  }

  @Test
  func detectedTransitionUsesCanonicalAliasesAndAxisThresholds() {
    let previous = ControllerState.neutral
    var current = previous
    current.pressed = [.microphone]
    #expect(
      RuntimePresentation.detectedTransition(from: previous, to: current)
        == .button(.microphone)
    )

    current.pressed = []
    current.leftStick.x = BipolarValue(normalized: 0.75)
    #expect(
      RuntimePresentation.detectedTransition(from: previous, to: current)
        == .axisDirection(.leftStickX, .positive)
    )

    var held = current
    held.leftStick.x = BipolarValue(normalized: 0.8)
    #expect(
      RuntimePresentation.detectedTransition(from: current, to: held) == nil
    )

    held.leftStick.x = BipolarValue(normalized: -0.8)
    #expect(
      RuntimePresentation.detectedTransition(from: current, to: held)
        == .axisDirection(.leftStickX, .negative)
    )
  }

  @Test
  func detectedTransitionIgnoresReleaseOnlyChanges() {
    var previous = ControllerState.neutral
    previous.pressed = [.south, .east]
    var current = previous
    current.pressed = [.east]

    #expect(
      RuntimePresentation.detectedTransition(from: previous, to: current) == nil
    )
  }

  private func touchSample(surface: ControllerTouchSurface, x: UInt16) -> ControllerTouchSample {
    ControllerTouchSample(
      surface: surface,
      timestamp: MonotonicTimestamp(nanoseconds: 0),
      contacts: [ControllerTouchContact(slot: 0, isActive: true, x: x, y: 10)]
    )
  }
}
