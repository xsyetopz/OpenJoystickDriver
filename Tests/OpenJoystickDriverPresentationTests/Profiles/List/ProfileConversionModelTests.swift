import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct ProfileConversionModelTests {
  private static let sourceModel = ControllerModelID(vendorID: 0x045E, productID: 0x028E)
  private static let targetModel = ControllerModelID(vendorID: 0x054C, productID: 0x09CC)

  private static func choice(
    _ model: ControllerModelID,
    group: ProfileControllerChoice.Group = .profiles
  ) -> ProfileControllerChoice {
    ProfileControllerChoice(
      id: "model-\(model.vendorID)-\(model.productID)",
      name: nil,
      vendorID: model.vendorID,
      productID: model.productID,
      family: nil,
      group: group
    )
  }

  private static func profile(
    named name: String = "Pad",
    bindings: [RemappingBinding] = []
  ) -> RemappingProfile {
    RemappingProfile(
      name: name,
      device: RemappingDeviceScope(
        vendorID: sourceModel.vendorID,
        productID: sourceModel.productID
      ),
      applicationScope: .global,
      bindings: bindings
    )
  }

  private static func capabilities(
    _ controls: Set<Control>
  ) -> (ControllerModelID) -> ControllerProfileCapabilities? {
    { _ in
      ControllerProfileCapabilities(
        physicalInput: ControllerCapabilities(controls: controls),
        physicalOutput: .none
      )
    }
  }

  private static func binding(_ source: RemappingSource) -> RemappingBinding {
    RemappingBinding(source: source, destination: .keyboard(key: .space, modifiers: []))
  }

  @Test
  func targetStartsAsFirstModelNotSources() {
    let model = ProfileConversionModel(
      source: Self.profile(),
      choices: [Self.choice(Self.sourceModel), Self.choice(Self.targetModel)],
      profiles: []
    )
    #expect(model.target?.model == Self.targetModel)
  }

  @Test
  func thereNoTargetWithoutChoices() {
    let model = ProfileConversionModel(source: Self.profile(), choices: [], profiles: [])
    #expect(model.target == nil)
    #expect(model.converted(capabilities: Self.capabilities([])) == nil)
  }

  @Test
  func pickedModelStaysTargetAfterItsSessionLeaves() {
    var model = ProfileConversionModel(
      source: Self.profile(),
      choices: [Self.choice(Self.targetModel, group: .connected)],
      profiles: []
    )
    model.picked = Self.choice(Self.targetModel, group: .connected)
    model.choices = [Self.choice(Self.targetModel)]
    #expect(model.target?.model == Self.targetModel)
    model.choices = [Self.choice(Self.sourceModel)]
    #expect(model.target == nil)
  }

  @Test
  func nameStartsAsSourceNameAndTargetIdentityMadeFree() {
    let source = Self.profile()
    var model = ProfileConversionModel(
      source: source,
      choices: [Self.choice(Self.targetModel)],
      profiles: [source]
    )
    #expect(model.name == "Pad 054C:09CC")
    model.profiles = [source, Self.profile(named: "pad 054c:09cc")]
    #expect(model.name == "Pad 054C:09CC 2")
    model.editedName = "Mine"
    #expect(model.name == "Mine")
  }

  @Test
  func takenOrBlankNameMakesNoConversion() {
    let source = Self.profile()
    var model = ProfileConversionModel(
      source: source,
      choices: [Self.choice(Self.targetModel)],
      profiles: [source]
    )
    model.editedName = " pad "
    #expect(model.isNameTaken)
    #expect(model.converted(capabilities: Self.capabilities([.south])) == nil)
    model.editedName = "  "
    #expect(model.converted(capabilities: Self.capabilities([.south])) == nil)
  }

  @Test
  func conversionKeepsWhatTargetHasAndNamesTargetModel() throws {
    let kept = Self.binding(.button(.south))
    let lost = Self.binding(.button(.leftPaddle1))
    let source = Self.profile(bindings: [kept, lost])
    var model = ProfileConversionModel(
      source: source,
      choices: [Self.choice(Self.targetModel)],
      profiles: [source]
    )
    model.editedName = " Converted "
    let result = try #require(model.converted(capabilities: Self.capabilities([.south])))
    #expect(result.profile.name == "Converted")
    #expect(result.profile.id != source.id)
    #expect(result.profile.device.vendorID == Self.targetModel.vendorID)
    #expect(result.profile.device.productID == Self.targetModel.productID)
    #expect(result.profile.bindings.map(\.source) == [.button(.south)])
    #expect(result.leftOut.map(\.section) == [.binding])
    #expect(result.leftOut.first?.sources == [.button(.leftPaddle1)])
  }

  @Test
  func reportListsEachPartLeftOutAndTarget() throws {
    let source = Self.profile(bindings: [Self.binding(.button(.leftPaddle1))])
    let model = ProfileConversionModel(
      source: source,
      choices: [Self.choice(Self.targetModel)],
      profiles: [source]
    )
    let result = try #require(model.converted(capabilities: Self.capabilities([.south])))
    let report = ProfileConversionReport(result)
    let section = OJDLocalized.string("ui.profiles.convert.section.binding")
    #expect(report.id == result.profile.id)
    #expect(report.profileName == result.profile.name)
    #expect(report.identity == "054C:09CC")
    #expect(report.lines.count == 1)
    #expect(report.lines.first?.contains(section) == true)
  }

  @Test
  func conversionLeavesNothingOutHasNoLines() throws {
    let source = Self.profile(bindings: [Self.binding(.button(.south))])
    let model = ProfileConversionModel(
      source: source,
      choices: [Self.choice(Self.targetModel)],
      profiles: [source]
    )
    let result = try #require(model.converted(capabilities: Self.capabilities([.south])))
    #expect(ProfileConversionReport(result).lines.isEmpty)
  }

  @Test
  func everyLeftOutSectionHasLocalizedName() {
    for section in RemappingProfileConversion.LeftOut.Section.allCases {
      let suffix = section.localizationSuffix
      let key = "ui.profiles.convert.section.\(suffix)"
      #expect(OJDLocalized.string("ui.profiles.convert.section.\(suffix)") != key)
    }
  }
}
