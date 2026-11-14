import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

/// What a guided check did to the outside world, in place of the file viewer, the browser and the
/// pasteboard.
@MainActor
private final class Effects {
  var revealed: [URL] = []
  var opened: [URL] = []
  var copied: [String] = []
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "guided-check-\(UUID().uuidString)",
    isDirectory: true
  )

  var environment: GuidedCheckEnvironment {
    GuidedCheckEnvironment(
      record: { _ in nil },
      saveDirectory: directory,
      reveal: { self.revealed.append($0) },
      open: { self.opened.append($0) },
      copy: { self.copied.append($0) }
    )
  }

  func model() -> GuidedCheckModel { GuidedCheckModel(environment: environment) }
}

@Suite("Guided check")
@MainActor
struct GuidedCheckTests {
  private let device = ApplicationServiceDeviceDescription.fixture(
    id: "pad",
    serialNumber: "SN-7F3A-SECRET",
    capabilities: ControllerCapabilities(controls: [.south, .east])
  )

  private func press(_ control: Control) -> ControllerState {
    var state = ControllerState.neutral
    state.pressed = [control]
    return state
  }

  private func finish(_ model: GuidedCheckModel, responding: Bool) {
    model.observe(.neutral)
    if responding {
      model.observe(press(.south))
      model.observe(.neutral)
      model.observe(press(.east))
    } else {
      model.skip()
      model.skip()
    }
  }

  @Test
  func stepsAreDrawnByTheLiveViewForEveryBundledRecord() {
    let registry = ProtocolDriverRegistry()
    var undrawn: [String] = []
    for model in ControllerRecordSet.bundled.records.keys {
      guard let declared = registry.profileCapabilities(for: model)?.physicalInput else {
        continue
      }
      let layout = InputTestControlLayout(capabilities: declared)
      let asked = ControllerCheckControl.steps(for: declared).flatMap { step -> [Control] in
        switch step {
        case .button(let control), .trigger(let control): [control]
        case .stick(let left):
          left ? [.leftStickX, .leftStickY] : [.rightStickX, .rightStickY]
        }
      }
      let missing = Set(asked).subtracting(layout.drawnControls)
      if !missing.isEmpty { undrawn.append("\(model): \(missing)") }
    }
    #expect(undrawn.isEmpty, "\(undrawn)")
  }

  @Test
  func theEndSheetOpensWhenTheLastStepEnds() {
    let model = Effects().model()
    model.start(device)
    #expect(model.run?.current == .button(.south))
    #expect(!model.isEndSheetPresented)

    finish(model, responding: true)

    #expect(model.run == nil)
    #expect(model.isEndSheetPresented)
    #expect(model.result?.steps.map(\.outcome) == [.responded, .responded])
  }

  @Test
  func cancelEndsARunWithoutAResult() {
    let model = Effects().model()
    model.start(device)
    model.observe(.neutral)
    model.cancel()
    model.observe(press(.south))

    #expect(model.run == nil)
    #expect(model.result == nil)
    #expect(!model.isEndSheetPresented)
  }

  @Test
  func openIssueSavesRevealsAndOpensAnAddressWithNoReportBody() throws {
    let effects = Effects()
    let model = effects.model()
    model.start(device)
    finish(model, responding: true)

    model.openIssue()

    let saved = try #require(effects.revealed.first)
    let document = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: saved)) as? [String: Any]
    )
    #expect(document["kind"] as? String == "ControllerCheck")
    #expect(document["apiVersion"] as? String == OpenJoystickDriverAPI.version)
    let text = try String(contentsOf: saved, encoding: .utf8)
    #expect(!text.contains("SN-7F3A-SECRET"))

    let url = try #require(effects.opened.first)
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(effects.opened.count == 1)
    #expect(items.map(\.name) == ["template", "version", "vid-pid", "connection", "mode"])
    #expect(items.first?.value == "controller-support.yml")
    for body in ["South", "East", "Responded", "steps"] {
      #expect(!url.absoluteString.contains(body))
    }
    #expect(model.failure == nil)
  }

  @Test
  func openIssueReportsAFailedSaveAndOpensNothing() {
    let effects = Effects()
    var environment = effects.environment
    environment.saveDirectory = URL(fileURLWithPath: "/dev/null/guided-check")
    let model = GuidedCheckModel(environment: environment)
    model.start(device)
    finish(model, responding: true)

    model.openIssue()

    #expect(model.failure != nil)
    #expect(effects.revealed.isEmpty)
    #expect(effects.opened.isEmpty)
  }

  @Test
  func copyPutsTheDocumentOnThePasteboard() throws {
    let effects = Effects()
    let model = effects.model()
    model.start(device)
    finish(model, responding: false)

    model.copy()

    let text = try #require(effects.copied.first)
    #expect(text.contains("ControllerCheck"))
    #expect(text.contains("Skipped"))
  }

  @Test
  func validateIsOfferedOnlyAfterACheckInWhichEveryControlResponded() {
    let responded = Effects().model()
    responded.start(device)
    finish(responded, responding: true)
    #expect(responded.validationText != nil)

    let skipped = Effects().model()
    skipped.start(device)
    finish(skipped, responding: false)
    #expect(skipped.validationText == nil)
  }

  @Test
  func validationTextHoldsNoSerialNumberUserNameOrPath() throws {
    let model = Effects().model()
    model.start(device)
    finish(model, responding: true)

    let text = try #require(model.validationText)
    for hidden in ["SN-7F3A-SECRET", NSUserName(), NSHomeDirectory(), "/Users/"] {
      #expect(!text.contains(hidden))
    }
  }

  @Test
  func confirmOpensTheValidationFormAndClosesTheSheet() throws {
    let effects = Effects()
    let model = effects.model()
    model.start(device)
    finish(model, responding: true)
    model.isValidationPresented = true

    model.confirmValidation()

    let url = try #require(effects.opened.first)
    #expect(effects.opened.count == 1)
    #expect(url.absoluteString.contains("template=controller-validation.yml"))
    #expect(!model.isValidationPresented)
  }

  @Test
  func confirmOpensNothingAfterACheckWithASkippedControl() {
    let effects = Effects()
    let model = effects.model()
    model.start(device)
    finish(model, responding: false)

    model.confirmValidation()

    #expect(effects.opened.isEmpty)
  }

  @Test
  func inputTestFeedsItsSamplesToARunAndDropsTheRunWhenTheWindowCloses() {
    let gateway = InputTestGatewayStub(inputSequence: [.neutral])
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)
    model.selectDevice(device)
    model.open()

    model.startGuidedCheck()
    #expect(model.guidedCheck.run?.current == .button(.south))
    model.close()

    #expect(model.guidedCheck.run == nil)
  }
}
