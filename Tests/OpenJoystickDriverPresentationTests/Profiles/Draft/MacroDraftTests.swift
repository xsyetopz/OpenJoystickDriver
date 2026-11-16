import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct MacroDraftTests {
  private static let profile = RemappingProfile(
    name: "Macros",
    device: RemappingDeviceScope(vendorID: 1, productID: 2),
    applicationScope: .global,
    outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
    bindings: []
  )

  private static func macro(_ name: String = "Combo") -> RemappingMacro {
    RemappingMacro(name: name, steps: [MacroStepKind.tap.newStep])
  }

  @Test
  func addingMacroKeepsItAndReplacesByID() throws {
    let macro = Self.macro()
    let added = try RuntimeProfileDraft(profile: Self.profile).settingMacro(macro)
    #expect(added.profile.macros == [macro])
    let renamed = RemappingMacro(id: macro.id, name: "Other", steps: macro.steps)
    let replaced = try added.settingMacro(renamed)
    #expect(replaced.profile.macros == [renamed])
  }

  @Test
  func duplicateNameIsRefused() throws {
    let added = try RuntimeProfileDraft(profile: Self.profile).settingMacro(Self.macro())
    #expect(throws: RuntimeProfileDraftError.self) { try added.settingMacro(Self.macro()) }
  }

  @Test
  func removingMacroDropsIt() throws {
    let macro = Self.macro()
    let draft = try RuntimeProfileDraft(profile: Self.profile).settingMacro(macro)
    #expect(try draft.removingMacro(macro.id).profile.macros.isEmpty)
  }

  @Test
  func removingUsedMacroIsRefused() throws {
    let macro = Self.macro()
    let draft = try RuntimeProfileDraft(profile: Self.profile).settingMacro(macro)
      .addingBinding(source: .button(.south), destination: .macro(macro.id))
    #expect(throws: RuntimeProfileDraftError.self) { try draft.removingMacro(macro.id) }
  }

  @Test
  func stepsAddReorderAndRemove() {
    var draft = MacroDraft()
    draft.addStep(.wait)
    draft.addStep(.chord)
    #expect(draft.steps.count == 3)
    draft.moveStep(at: 1, by: -1)
    #expect(draft.steps[0] == MacroStepKind.wait.newStep)
    draft.moveStep(at: 0, by: -1)
    #expect(draft.steps[0] == MacroStepKind.wait.newStep)
    draft.moveStep(at: 2, by: 1)
    #expect(draft.steps[2] == MacroStepKind.chord.newStep)
    draft.removeStep(at: 0)
    #expect(draft.steps == [MacroStepKind.tap.newStep, MacroStepKind.chord.newStep])
  }

  @Test
  func macroDestinationIsOfferedForDiscreteSourcesOnly() {
    let macro = Self.macro()
    let discrete = DestinationOption.options(for: .button(.south), macros: [macro])
    #expect(discrete.contains { $0.destination == .macro(macro.id) && $0.title == "Combo" })
    let axis = DestinationOption.options(for: .axis(.leftTrigger), macros: [macro])
    #expect(!axis.contains { $0.destination == .macro(macro.id) })
  }

  @Test
  func destinationLabelNamesMacro() {
    let macro = Self.macro()
    #expect(RuntimePresentation.destinationLabel(.macro(macro.id), macros: [macro]) == "Combo")
  }
}
