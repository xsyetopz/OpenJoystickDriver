import Carbon.HIToolbox
import CoreGraphics
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct CoreGraphicsSinkTests {
  @Test func everySymbolicKeyboardKeyHasAnOfficialVirtualKey() throws {
    let translator = MacVirtualKeyTranslator()
    for key in RemappingKeyboardKey.allCases {
      #expect(translator.virtualKey(for: key) != nil, "Missing virtual key for \(key)")
    }
    #expect(translator.virtualKey(for: .help) == CGKeyCode(kVK_Help))
    #expect(translator.virtualKey(for: .insert) == CGKeyCode(kVK_Help))
  }

  @Test func modifiersAndKeysPreservePressReleaseOrderAndFlags() throws {
    let poster = RecordingPoster()
    let sink = makeSink(poster: poster)

    try sink.send(.modifierDown(.shift))
    try sink.send(.modifierDown(.command))
    try sink.send(.keyDown(.a))
    try sink.send(.keyUp(.a))
    try sink.send(.modifierUp(.command))
    try sink.send(.modifierUp(.shift))

    #expect(poster.events == [
      .modifier(virtualKey: CGKeyCode(kVK_Shift), flags: [.shift]),
      .modifier(virtualKey: CGKeyCode(kVK_Command), flags: [.shift, .command]),
      .keyboard(virtualKey: CGKeyCode(kVK_ANSI_A), isDown: true, flags: [.shift, .command]),
      .keyboard(virtualKey: CGKeyCode(kVK_ANSI_A), isDown: false, flags: [.shift, .command]),
      .modifier(virtualKey: CGKeyCode(kVK_Command), flags: [.shift]),
      .modifier(virtualKey: CGKeyCode(kVK_Shift), flags: []),
    ])
  }

  @Test func everyModifierUsesItsPlatformKeyAndFlag() throws {
    let cases: [(RemappingKeyModifier, CGKeyCode, CoreGraphicsModifierFlags)] = [
      (.command, CGKeyCode(kVK_Command), .command),
      (.control, CGKeyCode(kVK_Control), .control),
      (.option, CGKeyCode(kVK_Option), .option),
      (.shift, CGKeyCode(kVK_Shift), .shift),
    ]
    for (modifier, virtualKey, flag) in cases {
      let poster = RecordingPoster()
      let sink = makeSink(poster: poster)
      try sink.send(.modifierDown(modifier))
      try sink.send(.modifierUp(modifier))
      #expect(poster.events == [
        .modifier(virtualKey: virtualKey, flags: flag),
        .modifier(virtualKey: virtualKey, flags: []),
      ])
    }
  }

  @Test func eachMouseButtonKeepsItsCoreGraphicsIdentity() throws {
    let poster = RecordingPoster(pointerLocation: CGPoint(x: 12, y: 34))
    let sink = makeSink(poster: poster)

    for button in RemappingMouseButton.allCases {
      try sink.send(.mouseButtonDown(button))
      try sink.send(.mouseButtonUp(button))
    }

    let identities: [CoreGraphicsMouseButton] = [.left, .right, .middle, .back, .forward]
    let expected = identities.flatMap { button in
      [
        CoreGraphicsPreparedEvent.mouseButton(
          button: button,
          isDown: true,
          location: CGPoint(x: 12, y: 34)
        ),
        CoreGraphicsPreparedEvent.mouseButton(
          button: button,
          isDown: false,
          location: CGPoint(x: 12, y: 34)
        ),
      ]
    }
    #expect(poster.events == expected)
  }

  @Test func pointerAmountsAreClampedScaledAndReadCurrentLocation() throws {
    let poster = RecordingPoster(pointerLocation: CGPoint(x: 100, y: 200))
    let sink = makeSink(poster: poster)

    try sink.send(.mouseMoved(axis: .x, amount: 4))
    poster.pointerLocation = CGPoint(x: 140, y: 210)
    try sink.send(.mouseMoved(axis: .y, amount: -4))

    #expect(poster.events == [
      .pointer(location: CGPoint(x: 132, y: 200), deltaX: 32, deltaY: 0),
      .pointer(location: CGPoint(x: 140, y: 178), deltaX: 0, deltaY: -32),
    ])
    #expect(poster.pointerReadCount == 2)

    try sink.send(.mouseMoved(axis: .x, amount: 0))
    poster.pointerLocation = CGPoint(x: 10, y: 20)
    try sink.send(.mouseMoved(axis: .x, amount: 0.5))
    #expect(poster.events.last == .pointer(
      location: CGPoint(x: 26, y: 20),
      deltaX: 16,
      deltaY: 0
    ))
    #expect(poster.pointerReadCount == 3)
  }

  @Test func scrollPreservesSubUnitResidualsAndAxisIdentity() throws {
    let poster = RecordingPoster()
    let sink = makeSink(poster: poster)

    try sink.send(.scrolled(axis: .y, amount: 0.05))
    try sink.send(.scrolled(axis: .y, amount: 0.05))
    #expect(poster.events.isEmpty)
    try sink.send(.scrolled(axis: .y, amount: 0.05))
    #expect(poster.events == [.scroll(deltaX: 0, deltaY: 1)])

    try sink.send(.scrolled(axis: .x, amount: -0.2))
    #expect(poster.events.last == .scroll(deltaX: -1, deltaY: 0))
  }

  @Test func neutralScrollClearsOnlyItsAxisResidual() throws {
    let poster = RecordingPoster()
    let sink = makeSink(poster: poster)

    try sink.send(.scrolled(axis: .x, amount: 0.1))
    try sink.send(.scrolled(axis: .y, amount: 0.1))
    try sink.send(.scrolled(axis: .x, amount: 0))
    try sink.send(.scrolled(axis: .x, amount: 0.05))
    try sink.send(.scrolled(axis: .y, amount: 0.05))

    #expect(poster.events == [.scroll(deltaX: 0, deltaY: 1)])
  }

  @Test func missingPreflightBlocksEveryPost() {
    let poster = RecordingPoster()
    let sink = makeSink(poster: poster, authorized: false)

    #expect(throws: CoreGraphicsSystemInputSinkError.postEventAccessNotGranted) {
      try sink.send(.keyDown(.a))
    }
    #expect(poster.events.isEmpty)
  }

  @Test func unsupportedKeyFailsBeforePosting() {
    let poster = RecordingPoster()
    let sink = makeSink(poster: poster, translator: UnsupportedKeyTranslator())

    #expect(throws: CoreGraphicsSystemInputSinkError.unsupportedKeyboardKey(.a)) {
      try sink.send(.keyDown(.a))
    }
    #expect(poster.events.isEmpty)
  }

  @Test func creationAndPostingFailuresUseStableErrors() {
    let creationPoster = RecordingPoster(failure: .creation)
    let creationSink = makeSink(poster: creationPoster)
    #expect(throws: CoreGraphicsSystemInputSinkError.eventPreparationFailed) {
      try creationSink.send(.keyDown(.a))
    }

    let postingPoster = RecordingPoster(failure: .posting)
    let postingSink = makeSink(poster: postingPoster)
    #expect(throws: CoreGraphicsSystemInputSinkError.eventPostingFailed) {
      try postingSink.send(.keyDown(.a))
    }
  }

  @Test func invalidContinuousAmountFailsWithoutPosting() {
    let poster = RecordingPoster()
    let sink = makeSink(poster: poster)

    #expect(throws: CoreGraphicsSystemInputSinkError.eventPreparationFailed) {
      try sink.send(.mouseMoved(axis: .x, amount: .infinity))
    }
    #expect(throws: CoreGraphicsSystemInputSinkError.eventPreparationFailed) {
      try sink.send(.scrolled(axis: .y, amount: .nan))
    }
    #expect(poster.events.isEmpty)
  }

  private func makeSink(
    poster: RecordingPoster,
    authorized: Bool = true,
    translator: any CoreGraphicsKeyboardTranslating = MacVirtualKeyTranslator()
  ) -> CoreGraphicsSystemInputSink {
    CoreGraphicsSystemInputSink(
      access: CoreGraphicsPostEventAccess(
        probe: AccessProbe(preflight: [authorized], requestResult: false)
      ),
      poster: poster,
      translator: translator
    )
  }
}

private struct UnsupportedKeyTranslator: CoreGraphicsKeyboardTranslating {
  func virtualKey(for _: RemappingKeyboardKey) -> CGKeyCode? { nil }
}

private enum PosterFailure {
  case creation
  case posting
}

private enum SyntheticPostingError: Error {
  case failed
}

private final class RecordingPoster: CoreGraphicsEventPosting, @unchecked Sendable {
  var events: [CoreGraphicsPreparedEvent] = []
  var pointerLocation: CGPoint
  private(set) var pointerReadCount = 0
  private let failure: PosterFailure?

  init(pointerLocation: CGPoint = .zero, failure: PosterFailure? = nil) {
    self.pointerLocation = pointerLocation
    self.failure = failure
  }

  func currentPointerLocation() throws -> CGPoint {
    pointerReadCount += 1
    if failure == .creation { throw CoreGraphicsEventPosterError.eventCreationFailed }
    if failure == .posting { throw SyntheticPostingError.failed }
    return pointerLocation
  }

  func post(_ event: CoreGraphicsPreparedEvent) throws {
    if failure == .creation { throw CoreGraphicsEventPosterError.eventCreationFailed }
    if failure == .posting { throw SyntheticPostingError.failed }
    events.append(event)
  }
}
