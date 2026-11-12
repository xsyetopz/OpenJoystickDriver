import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct SystemActionTests {
  private let identifier = LogicalControllerID(vendorID: 1, productID: 2, locationID: 1)

  // MARK: Coding and validation

  @Test
  func destinationsRoundTripAsTheirDocumentShape() throws {
    let cases: [(RemappingDestination, String)] = [
      (.systemKey(.volumeUp), #"{"systemKey":"VolumeUp","type":"SystemKey"}"#),
      (.systemAction(.missionControl), #"{"action":"MissionControl","type":"SystemAction"}"#),
      (.systemAction(.launchpad), #"{"action":"Launchpad","type":"SystemAction"}"#),
      (.systemAction(.screenshot), #"{"action":"Screenshot","type":"SystemAction"}"#),
      (
        .openApplication(bundleIdentifier: "com.apple.TextEdit"),
        #"{"bundleIdentifier":"com.apple.TextEdit","type":"OpenApplication"}"#
      ),
      (.openURL("steam://open/main"), #"{"type":"OpenURL","url":"steam://open/main"}"#),
      (.runShortcut("Morning"), #"{"name":"Morning","type":"RunShortcut"}"#),
      (.typeText("hello"), #"{"text":"hello","type":"TypeText"}"#),
    ]
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    for (destination, json) in cases {
      let data = try encoder.encode(destination)
      #expect(String(bytes: data, encoding: .utf8) == json)
      #expect(try JSONDecoder().decode(RemappingDestination.self, from: data) == destination)
    }
  }

  @Test
  func badShapesAreRejected() {
    let rejected = [
      #"{"type":"SystemKey","systemKey":"Eject"}"#,
      #"{"type":"SystemKey","systemKey":"Mute","text":"a"}"#,
      #"{"type":"SystemAction","action":"LockScreen"}"#,
      #"{"type":"TypeText"}"#,
      #"{"type":"OpenURL","name":"x"}"#,
    ]
    for json in rejected {
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(RemappingDestination.self, from: Data(json.utf8))
      }
    }
  }

  @Test
  func invalidValuesAreRejectedByName() throws {
    let invalid: [(RemappingDestination, String)] = [
      (.openURL("not a url"), "OpenURL"),
      (.openURL("/tmp/file"), "OpenURL"),
      (.openURL("file:///etc/hosts"), "OpenURL"),
      (.runShortcut(""), "RunShortcut"),
      (.runShortcut(String(repeating: "a", count: 51)), "RunShortcut"),
      (.typeText(""), "TypeText"),
      (.typeText(String(repeating: "a", count: 129)), "TypeText"),
      (.openApplication(bundleIdentifier: ""), "OpenApplication"),
    ]
    for (destination, name) in invalid {
      #expect(throws: RemappingValidationError.invalidSystemAction(action: name)) {
        try profile(destination).validate()
      }
    }
    for destination in [
      RemappingDestination.openURL("steam://open/main"), .runShortcut("Morning"),
      .typeText("hello"), .systemKey(.mute), .systemAction(.missionControl),
      .openApplication(bundleIdentifier: "com.apple.TextEdit"),
    ] { try profile(destination).validate() }
  }

  @Test
  func triggerActionsTakeOnlyPressBehaviors() throws {
    let triggers: [RemappingDestination] = [
      .systemAction(.missionControl), .openURL("steam://x"), .runShortcut("S"), .typeText("a"),
      .openApplication(bundleIdentifier: "com.apple.TextEdit"),
    ]
    for destination in triggers {
      for behavior in [RemappingBindingBehavior.toggle, .release, .pulse] {
        #expect(throws: RemappingValidationError.bindingBehaviorConflict(index: 0)) {
          try profile(destination, behavior: behavior).validate()
        }
      }
      try profile(destination, behavior: .tapOnPress).validate()
    }
  }

  @Test
  func actionsNeedPostEventOnlyForKeysAndText() {
    #expect(profile(.systemKey(.mute)).neededPermissions == [.postEvent])
    #expect(profile(.typeText("a")).neededPermissions == [.postEvent])
    let passthrough = RemappingOutputPolicy(virtualGamepad: .passthrough)
    #expect(profile(.openURL("steam://x"), policy: passthrough).neededPermissions.isEmpty)
  }

  // MARK: Engine

  @Test
  func eachSystemKeySendsDownThenUp() {
    for key in RemappingSystemKey.allCases {
      var state = RemappingEngineState()
      let profile = profile(.systemKey(key))
      #expect(press(&state, profile) == [.systemAction(.key(key, pressed: true))])
      #expect(release(&state, profile) == [.systemAction(.key(key, pressed: false))])
    }
  }

  @Test
  func triggerActionsFireOnPressOnly() {
    let cases: [(RemappingDestination, RemappingSystemActionRequest)] = [
      (.systemAction(.missionControl), .missionControl),
      (.systemAction(.launchpad), .launchpad),
      (.systemAction(.screenshot), .screenshot),
      (
        .openApplication(bundleIdentifier: "com.apple.TextEdit"),
        .openApplication("com.apple.TextEdit")
      ),
      (.openURL("https://example.com"), .openURL("https://example.com")),
      (.runShortcut("Morning"), .runShortcut("Morning")),
      (.typeText("hello"), .typeText("hello")),
    ]
    for (destination, request) in cases {
      var state = RemappingEngineState()
      let profile = profile(destination)
      #expect(press(&state, profile) == [.systemAction(request)])
      #expect(release(&state, profile).isEmpty)
    }
  }

  @Test
  func performerReceivesEachActionOnce() async throws {
    let performer = StubPerformer()
    let engine = RemappingEventEngine(sink: RemappingTestSink(), systemActionPerformer: performer)
    let cases: [(RemappingDestination, String)] = [
      (.systemAction(.missionControl), "missionControl"),
      (.systemAction(.launchpad), "launchpad"),
      (.systemAction(.screenshot), "screenshot"),
      (.openApplication(bundleIdentifier: "com.apple.TextEdit"), "app:com.apple.TextEdit"),
      (.openURL("https://example.com"), "url:https://example.com"),
      (.runShortcut("Morning"), "shortcut:Morning"),
      (.typeText("hello"), "text:hello"),
      (.systemKey(.volumeUp), "key:VolumeUp:down"),
    ]
    for (destination, expected) in cases {
      let profile = profile(destination)
      try await engine.process(event(down: true), from: identifier, using: profile, at: 0)
      try await performer.wait(for: expected)
      #expect(performer.calls.filter { $0 == expected }.count == 1)
      try await engine.process(event(down: false), from: identifier, using: profile, at: 1)
    }
    #expect(performer.calls.last == "key:VolumeUp:up")
  }

  @Test
  func failingPerformerReportsANamedError() async throws {
    let performer = StubPerformer(
      failure: RemappingSystemActionError.failed(action: "RunShortcut", reason: "missing")
    )
    let reporter = ErrorRecorder()
    let engine = RemappingEventEngine(
      sink: RemappingTestSink(),
      systemActionPerformer: performer
    ) { reporter.record($0) }
    try await engine.process(
      event(down: true),
      from: identifier,
      using: profile(.runShortcut("Nope")),
      at: 0
    )
    try await performer.wait(for: "shortcut:Nope")
    try await reporter.wait()
    let error = try #require(reporter.errors.first as? RemappingSystemActionError)
    #expect(error.errorCode == .systemActionFailed)
    #expect(error.errorDescription?.contains("RunShortcut") == true)
    #expect(error.errorDescription?.contains("missing") == true)
  }

  @Test
  func secureInputHasItsOwnCode() {
    #expect(RemappingSystemActionError.secureInputEnabled.errorCode == .secureInputEnabled)
  }

  // MARK: Helpers

  private func event(down: Bool) -> ControllerEvent {
    ControllerEvent(
      timestamp: MonotonicTimestamp(nanoseconds: 0),
      state: ControllerState(pressed: down ? [.south] : [])
    )
  }

  private func press(
    _ state: inout RemappingEngineState,
    _ profile: RemappingProfile
  ) -> [RemappingEngineAction] {
    state.process(inputs: [.press(.south)], from: identifier, profile: profile, at: 0)
  }

  private func release(
    _ state: inout RemappingEngineState,
    _ profile: RemappingProfile
  ) -> [RemappingEngineAction] {
    state.process(inputs: [.release(.south)], from: identifier, profile: profile, at: 0)
  }

  private func profile(
    _ destination: RemappingDestination,
    behavior: RemappingBindingBehavior = .hold,
    policy: RemappingOutputPolicy = .systemInput
  ) -> RemappingProfile {
    RemappingProfile(
      name: "P",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: policy,
      bindings: [
        RemappingBinding(source: .button(.south), destination: destination, behavior: behavior)
      ]
    )
  }
}

// swiftlint:disable async_without_await

/// Records what the engine asks for, and fails every call with `failure` when one is given.
private final class StubPerformer: RemappingSystemActionPerforming, @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [String] = []
  private let failure: (any Error)?

  init(failure: (any Error)? = nil) { self.failure = failure }

  var calls: [String] { lock.withLock { recorded } }

  func wait(for call: String) async throws {
    for _ in 0..<200 {
      if calls.contains(call) { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("The performer never received \(call).")
  }

  private func record(_ call: String) throws {
    lock.withLock { recorded.append(call) }
    if let failure { throw failure }
  }

  func postSystemKey(_ key: RemappingSystemKey, pressed: Bool) async throws {
    try record("key:\(key.rawValue):\(pressed ? "down" : "up")")
  }
  func openMissionControl() async throws { try record("missionControl") }
  func openLaunchpad() async throws { try record("launchpad") }
  func openScreenshot() async throws { try record("screenshot") }
  func openApplication(bundleIdentifier: String) async throws {
    try record("app:\(bundleIdentifier)")
  }
  func openURL(_ url: URL) async throws { try record("url:\(url.absoluteString)") }
  func runShortcut(name: String) async throws { try record("shortcut:\(name)") }
  func typeText(_ text: String) async throws { try record("text:\(text)") }
}

// swiftlint:enable async_without_await

/// Collects the failures that the engine reports.
private final class ErrorRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [any Error] = []

  var errors: [any Error] { lock.withLock { recorded } }

  func record(_ error: any Error) { lock.withLock { recorded.append(error) } }

  func wait() async throws {
    for _ in 0..<200 {
      if !errors.isEmpty { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("No failure was reported.")
  }
}
