import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

struct ProfileCreationFieldsTests {
  private static func device(
    _ name: String,
    token: String,
    vendorID: UInt16,
    productID: UInt16
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: name,
      vendorID: vendorID,
      productID: productID,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system,
      sessionToken: .fixture(token)
    )
  }

  private static let padA = device("Pad A", token: "a", vendorID: 0x0001, productID: 0x0002)
  private static let padB = device("Pad B", token: "b", vendorID: 0x0003, productID: 0x0004)

  private static func context(
    devices: [ApplicationServiceDeviceDescription],
    profiles: [RemappingProfile] = [],
    catalog: [ControllerModelID: PhysicalProtocolID] = [:]
  ) -> ProfileCreationContext {
    ProfileCreationContext(
      choices: ProfileControllerChoice.choices(
        devices: devices,
        profiles: profiles,
        catalog: catalog
      ),
      profiles: profiles
    )
  }

  private static func profile(
    named name: String,
    vendorID: UInt16 = 9,
    productID: UInt16 = 7
  ) -> RemappingProfile {
    RemappingProfile(
      name: name,
      device: RemappingDeviceScope(vendorID: vendorID, productID: productID),
      applicationScope: .global,
      bindings: []
    )
  }

  @Test
  func theFirstControllerIsChosenAndNamesTheProfile() {
    let context = Self.context(devices: [Self.padA, Self.padB])
    let fields = ProfileCreationFields()
    #expect(fields.controller(in: context)?.id == Self.padA.sessionToken.rawValue)
    #expect(fields.name(in: context) == "Pad A")
    #expect(fields.proposedProfile(in: context)?.device.vendorID == 0x0001)
  }

  @Test
  func withNothingToChooseNothingIsProposed() {
    let context = Self.context(devices: [])
    let fields = ProfileCreationFields()
    #expect(fields.controller(in: context) == nil)
    #expect(fields.name(in: context).isEmpty)
    #expect(fields.proposedProfile(in: context) == nil)
  }

  @Test
  func anUntouchedNameFollowsTheChosenController() {
    let context = Self.context(devices: [Self.padA, Self.padB])
    var fields = ProfileCreationFields()
    fields.picked = context.choices[1]
    #expect(fields.name(in: context) == "Pad B")
    #expect(
      fields.proposedProfile(in: context)?.device
        == RemappingDeviceScope(vendorID: 0x0003, productID: 0x0004)
    )
  }

  @Test
  func anEditedNameStaysWhenAnotherControllerIsChosen() {
    let context = Self.context(devices: [Self.padA, Self.padB])
    var fields = ProfileCreationFields()
    fields.editedName = "Racing"
    fields.picked = context.choices[1]
    #expect(fields.name(in: context) == "Racing")
  }

  @Test
  func aPickedControllerThatDisconnectsStaysOnItsModelWithItsName() {
    let both = Self.context(devices: [Self.padA, Self.padB])
    var fields = ProfileCreationFields()
    fields.picked = both.choices[1]
    let gone = Self.context(
      devices: [Self.padA],
      profiles: [Self.profile(named: "Old", vendorID: 0x0003, productID: 0x0004)]
    )
    let resolved = fields.controller(in: gone)
    #expect(resolved?.model == ControllerModelID(vendorID: 0x0003, productID: 0x0004))
    #expect(resolved?.id != Self.padA.sessionToken.rawValue)
    #expect(fields.name(in: gone) == "Pad B")
    #expect(
      fields.proposedProfile(in: gone)?.device
        == RemappingDeviceScope(vendorID: 0x0003, productID: 0x0004)
    )
  }

  @Test
  func aPickedControllerWhoseModelIsNoLongerOfferedLeavesNoControllerAndNoProfile() {
    let both = Self.context(devices: [Self.padA, Self.padB])
    var fields = ProfileCreationFields()
    fields.picked = both.choices[1]
    let gone = Self.context(devices: [Self.padA])
    #expect(fields.controller(in: gone) == nil)
    #expect(fields.proposedProfile(in: gone) == nil)
  }

  @Test
  func withNothingConnectedAndNothingPickedNoModelIsPreselected() {
    let context = Self.context(
      devices: [],
      catalog: [ControllerModelID(vendorID: 0x054C, productID: 0x0CE6): .sonyDualSense]
    )
    let fields = ProfileCreationFields()
    #expect(!context.choices.isEmpty)
    #expect(fields.controller(in: context) == nil)
    #expect(fields.proposedProfile(in: context) == nil)
  }

  @Test
  func aControllerThatArrivesAfterTheSheetOpenedIsChosenWithItsName() {
    let fields = ProfileCreationFields()
    #expect(fields.proposedProfile(in: Self.context(devices: [])) == nil)
    let arrived = Self.context(devices: [Self.padB])
    #expect(fields.name(in: arrived) == "Pad B")
    #expect(fields.proposedProfile(in: arrived) != nil)
  }

  @Test
  func aBlankNameProposesNoProfile() {
    var fields = ProfileCreationFields()
    fields.editedName = "  "
    #expect(fields.proposedProfile(in: Self.context(devices: [Self.padA])) == nil)
  }

  @Test
  func connectedControllersComeFirstThenProfileModelsThenCatalogModels() {
    let choices = ProfileControllerChoice.choices(
      devices: [Self.padA],
      profiles: [Self.profile(named: "Old", vendorID: 0x0001), Self.profile(named: "Other")],
      catalog: [
        ControllerModelID(vendorID: 9, productID: 7): .xboxGIP,
        ControllerModelID(vendorID: 0x0A, productID: 1): .xboxGIP,
        ControllerModelID(vendorID: 0x045E, productID: 0x02EA): .xboxGIP,
        ControllerModelID(vendorID: 0x054C, productID: 0x0CE6): .sonyDualSense,
        ControllerModelID(vendorID: 0x0001, productID: 0x0002): .xboxGIP,
      ]
    )
    let gip = PhysicalProtocolID.xboxGIP.displayName
    #expect(
      choices.map(\.label) == [
        "Pad A", "0001:0007", "\(gip) · 0009:0007", "054C:0CE6", "000A:0001", "045E:02EA",
      ]
    )
    let sections = ProfileControllerGroup.sections(of: choices)
    #expect(
      sections.map(\.title) == [
        OJDLocalized.string("ui.settings.notifications.controllerConnectedShort"),
        OJDLocalized.string("ui.profiles.controllersOfProfiles"),
        PhysicalProtocolID.sonyDualSense.displayName, gip,
      ]
    )
    #expect(
      sections.map(\.id) == [.connected, .profiles, .family(.sonyDualSense), .family(.xboxGIP)]
    )
    #expect(sections.map(\.choices.count) == [1, 2, 1, 2])
  }

  @Test
  func twoFamiliesThatShareATitleStayInSectionsOfTheirOwn() {
    let choices = ProfileControllerChoice.choices(
      devices: [],
      profiles: [],
      catalog: [
        ControllerModelID(vendorID: 1, productID: 1): .valveSteamController,
        ControllerModelID(vendorID: 1, productID: 2): .valveSteamDeck,
        ControllerModelID(vendorID: 1, productID: 3): .valveSteamController,
      ]
    )
    let sections = ProfileControllerGroup.sections(of: choices) { group in
      if case .family = group { return "Valve" }
      return ProfileControllerGroup.title(of: group)
    }
    #expect(sections.map(\.title) == ["Valve", "Valve"])
    #expect(Set(sections.map(\.id)) == [.family(.valveSteamController), .family(.valveSteamDeck)])
    #expect(sections.map(\.choices.count).sorted() == [1, 2])
    for section in sections {
      #expect(section.choices.allSatisfy { $0.group == section.group })
    }
  }

  @Test
  func aProfileCanTargetAModelThatIsNotConnected() {
    let context = Self.context(
      devices: [],
      catalog: [ControllerModelID(vendorID: 0x054C, productID: 0x0CE6): .sonyDualSense]
    )
    var fields = ProfileCreationFields()
    fields.picked = context.choices[0]
    fields.editedName = "Offline"
    let profile = fields.proposedProfile(in: context)
    #expect(profile?.device == RemappingDeviceScope(vendorID: 0x054C, productID: 0x0CE6))
  }

  @Test
  func theDefaultNameGetsANumberWhenTaken() {
    let context = Self.context(
      devices: [Self.padA],
      profiles: [Self.profile(named: "pad a"), Self.profile(named: "Pad A 2")]
    )
    let fields = ProfileCreationFields()
    #expect(fields.name(in: context) == "Pad A 3")
    #expect(fields.proposedProfile(in: context) != nil)
  }

  @Test
  func aTypedNameThatIsTakenProposesNoProfile() {
    let context = Self.context(devices: [Self.padA], profiles: [Self.profile(named: "Racing")])
    var fields = ProfileCreationFields()
    fields.editedName = " RACING "
    #expect(fields.isNameTaken(in: context))
    #expect(fields.proposedProfile(in: context) == nil)
  }

  @Test
  func theOutputPolicyStartsAsTheCLIStartsAndIsKept() {
    let context = Self.context(devices: [Self.padA])
    var fields = ProfileCreationFields()
    #expect(
      fields.proposedProfile(in: context)?.outputPolicy
        == RemappingOutputPolicy(virtualGamepad: .passthrough, physicalInput: .shared)
    )
    fields.outputPolicy = RemappingOutputPolicy(virtualGamepad: .mapped, physicalInput: .exclusive)
    #expect(
      fields.proposedProfile(in: context)?.outputPolicy
        == RemappingOutputPolicy(virtualGamepad: .mapped, physicalInput: .exclusive)
    )
  }

  @Test
  func anApplicationTargetNeedsAnAppID() {
    let context = Self.context(devices: [Self.padA])
    var fields = ProfileCreationFields()
    fields.scopeKind = .application
    fields.appIDs = []
    #expect(fields.proposedProfile(in: context) == nil)
    fields.appIDs = ["com.apple.Safari"]
    #expect(
      fields.proposedProfile(in: context)?.applicationScope
        == .application(appIDs: ["com.apple.Safari"])
    )
  }

  @Test
  func validationIsHiddenUntilAFieldIsEdited() {
    let untouched = ProfileCreationFields()
    #expect(!untouched.showsValidation(isValid: false))

    var edited = untouched
    edited.editedName = "Racing"
    #expect(edited.showsValidation(isValid: false))
    #expect(!edited.showsValidation(isValid: true))
  }

  @Test
  func theChosenOutputPolicyIsTheProposedProfilesPolicy() {
    let context = Self.context(devices: [Self.padA])
    var fields = ProfileCreationFields()
    #expect(
      fields.proposedProfile(in: context)?.outputPolicy
        == RemappingOutputPolicy(virtualGamepad: .passthrough, physicalInput: .shared)
    )
    fields.outputPolicy = RemappingOutputPolicy(
      virtualGamepad: .disabled,
      physicalInput: .exclusive
    )
    #expect(fields.proposedProfile(in: context)?.outputPolicy == fields.outputPolicy)
  }

  @Test
  func theGyroStickTemplateProposesAStickProfileForAModelWithMotion() {
    let dualSense = Self.device("DualSense", token: "d", vendorID: 0x054C, productID: 0x0CE6)
    let context = Self.context(devices: [dualSense])
    var fields = ProfileCreationFields()
    fields.template = .gyroStick
    fields.gyroStick = .left

    #expect(fields.lacksMotion(in: context) == false)
    #expect(fields.proposedProfile(in: context)?.gyroOutput.mode == .leftStick)
  }

  @Test
  func theGyroStickTemplateProposesNothingForAModelWithoutMotion() {
    let context = Self.context(devices: [Self.padA])
    var fields = ProfileCreationFields()
    fields.template = .gyroStick

    #expect(fields.lacksMotion(in: context))
    #expect(fields.proposedProfile(in: context) == nil)
  }
}
