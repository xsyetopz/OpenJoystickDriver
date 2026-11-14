import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

@Suite("Controller check")
struct ControllerCheckTests {
  private static let record = ControllerRecordSet.bundled.records[
    ControllerModelID(vendorID: 0x045E, productID: 0x028E)
  ]

  private func check(
    steps: [ControllerCheck.Step],
    serialNumber: String? = nil,
    record: ControllerRecord? = Self.record
  ) -> ControllerCheck {
    ControllerCheck(
      device: .fixture(id: "check", serialNumber: serialNumber),
      record: record,
      steps: steps,
      appVersion: "0.6.0-alpha.3",
      osVersion: "15.6.1"
    )
  }

  private func step(
    _ control: String,
    _ outcome: ControllerCheck.Outcome = .responded
  ) -> ControllerCheck.Step {
    ControllerCheck.Step(control: control, outcome: outcome, otherControl: nil, ranges: [])
  }

  @Test
  func stepsFollowControlOrderWithOneStepPerStick() {
    let capabilities = ControllerCapabilities(
      controls: [
        .south, .leftTrigger, .dpadUp, .leftStickX, .leftStickY, .rightStickX, .pointerX,
        .pointerTracking,
      ],
      touchContactCount: 0,
      motion: false
    )

    #expect(
      ControllerCheckControl.steps(for: capabilities) == [
        .button(.south), .trigger(.leftTrigger), .button(.dpadUp), .stick(left: true),
        .stick(left: false),
      ]
    )
  }

  @Test
  func buttonEndsItsStepWhenItLeavesRest() {
    var run = ControllerCheckRun(controls: [.button(.south), .button(.east)])
    run.observe(.neutral)
    run.observe(ControllerState(pressed: [.south]))

    #expect(run.results.map(\.outcome) == [.responded])
    #expect(run.current == .button(.east))
  }

  @Test
  func controlHeldAtTheStartIsIgnoredUntilReleased() {
    var run = ControllerCheckRun(controls: [.button(.south)])
    run.observe(ControllerState(pressed: [.south]))
    run.observe(ControllerState(pressed: [.south]))
    #expect(run.results.isEmpty)

    run.observe(.neutral)
    run.observe(ControllerState(pressed: [.south]))
    #expect(run.results.map(\.outcome) == [.responded])
  }

  @Test
  func anotherControlMovingEndsTheStepAndNamesIt() throws {
    var run = ControllerCheckRun(controls: [.button(.south), .button(.east)])
    run.observe(.neutral)
    run.observe(ControllerState(pressed: [.west]))

    let first = try #require(run.results.first)
    #expect(first.outcome == .otherControl)
    #expect(first.otherControl == "West")
    #expect(run.current == .button(.east))

    run.observe(ControllerState(pressed: [.west]))
    #expect(run.results.count == 1)
  }

  @Test
  func dpadReadsTheHat() {
    var run = ControllerCheckRun(controls: [.button(.dpadUp), .button(.dpadRight)])
    run.observe(.neutral)
    run.observe(ControllerState(hat: .northEast))

    #expect(run.results.map(\.outcome) == [.responded])
    #expect(run.current == .button(.dpadRight))
  }

  @Test
  func stickKeepsTheRangeSeenAndEndsAtRest() throws {
    var run = ControllerCheckRun(controls: [.stick(left: true)])
    run.observe(.neutral)
    run.observe(ControllerState(leftStick: StickPosition(x: .max, y: .center)))
    #expect(run.results.isEmpty)
    run.observe(ControllerState(leftStick: StickPosition(x: .min, y: .center)))
    run.observe(.neutral)

    let result = try #require(run.results.first)
    #expect(result.outcome == .responded)
    #expect(
      result.ranges == [
        ControllerCheck.Range(axis: "LeftStickX", min: -32767, max: 32767),
        ControllerCheck.Range(axis: "LeftStickY", min: 0, max: 0),
      ]
    )
  }

  @Test
  func skipEndsTheStep() {
    var run = ControllerCheckRun(controls: [.button(.south), .trigger(.leftTrigger)])
    run.observe(.neutral)
    run.skip()

    #expect(run.results.map(\.outcome) == [.skipped])
    #expect(run.current == .trigger(.leftTrigger))
    run.skip()
    run.skip()
    #expect(run.isFinished)
    #expect(run.results.count == 2)
  }

  @Test
  func onlyACheckWhereEveryControlRespondedOffersValidation() {
    let responded = check(steps: [step("South"), step("East")])
    #expect(responded.allResponded)
    #expect(ControllerCheckIssue.validationText(for: responded) != nil)

    for outcome in [ControllerCheck.Outcome.skipped, .otherControl] {
      let failed = check(steps: [step("South"), step("East", outcome)])
      #expect(!failed.allResponded)
      #expect(ControllerCheckIssue.validationText(for: failed) == nil)
    }
    #expect(ControllerCheckIssue.validationText(for: check(steps: [])) == nil)
  }

  @Test
  func aControllerWithNoRecordOffersNoValidation() {
    let unrecorded = check(steps: [step("South"), step("East")], record: nil)
    #expect(unrecorded.allResponded)
    #expect(ControllerCheckIssue.validationText(for: unrecorded) == nil)
  }

  @Test
  func validationTextHoldsNoSerialNumberAddressUserNameOrPath() throws {
    let serial = "SN-7F3A-SECRET"
    let validated = check(steps: [step("South"), step("LeftStick")], serialNumber: serial)
    let text = try #require(ControllerCheckIssue.validationText(for: validated))
    let url = ControllerCheckIssue.validationURL(for: validated).absoluteString

    for hidden in [serial, NSUserName(), NSHomeDirectory(), "/Users/", "Test Pad"] {
      #expect(!text.contains(hidden))
      #expect(!url.contains(hidden))
    }
    #expect(text.contains("VID:PID: 045e:028e"))
    #expect(text.contains("Connection: USB cable"))
  }

  @Test
  func issueAddressesHoldShortFieldsAndNoReportBody() throws {
    let steps = (0..<40).map { step("Auxiliary\($0)") }
    let long = check(steps: steps)

    let support = ControllerCheckIssue.supportURL(for: long)
    let items = try #require(
      URLComponents(url: support, resolvingAgainstBaseURL: false)?.queryItems
    )

    #expect(support.absoluteString.hasPrefix(ControllerCheckIssue.newIssue + "?"))
    #expect(
      items.map(\.name) == ["template", "version", "vid-pid", "connection", "mode"]
    )
    #expect(items.first { $0.name == "vid-pid" }?.value == "045e:028e")
    #expect(support.absoluteString.count < 300)
    #expect(!support.absoluteString.contains("Auxiliary"))
  }

  @Test
  func connectionNamesAnOptionOfTheForm() {
    let validated = check(steps: [step("South")])
    let url = ControllerCheckIssue.validationURL(for: validated)
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

    #expect(items.first { $0.name == "template" }?.value == "controller-validation.yml")
    #expect(items.first { $0.name == "connection" }?.value == "USB cable")
  }

  @Test
  func eachPrefilledFieldNamesAFieldOfItsForm() throws {
    let templates = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".github/ISSUE_TEMPLATE")
    let validated = check(steps: [step("South")])

    for url in [
      ControllerCheckIssue.supportURL(for: validated),
      ControllerCheckIssue.validationURL(for: validated),
    ] {
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      let name = try #require(items.first { $0.name == "template" }?.value)
      let form = try String(contentsOf: templates.appendingPathComponent(name), encoding: .utf8)
      for item in items where item.name != "template" {
        #expect(form.contains("id: \(item.name)\n"), "\(name) has no field \(item.name)")
      }
      let connection = try #require(items.first { $0.name == "connection" }?.value)
      #expect(form.contains("- \(connection)\n"), "\(name) offers no option \(connection)")
    }
  }

  @Test
  func documentTextAddsTheEnvelopeToTheFields() throws {
    let text = try check(steps: [step("South")]).documentText()
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
    )

    #expect(object["kind"] as? String == "ControllerCheck")
    #expect(object["apiVersion"] as? String == OpenJoystickDriverAPI.version)
    #expect(
      Set(object.keys) == [
        "apiVersion", "kind", "controller", "modeID", "recordSource", "appVersion", "osVersion",
        "steps",
      ]
    )
  }

  @Test
  func documentEncodesCamelCaseFieldsWithoutTheSerialNumber() throws {
    let encoded = try JSONEncoder().encode(
      check(steps: [step("South")], serialNumber: "SN-7F3A-SECRET")
    )
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    #expect(
      Set(object.keys) == [
        "controller", "modeID", "recordSource", "appVersion", "osVersion", "steps",
      ]
    )
    #expect(try !#require(String(bytes: encoded, encoding: .utf8)).contains("SN-7F3A-SECRET"))
  }
}
