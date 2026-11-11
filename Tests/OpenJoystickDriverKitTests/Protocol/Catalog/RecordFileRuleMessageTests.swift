import Testing

@testable import OpenJoystickDriverKit

@Suite
struct RecordFileRuleMessageTests {
  private static func message(_ key: String, _ arguments: [String] = []) -> String {
    ControllerRecordSet.problemDescription(
      ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.\(key)",
        arguments: arguments,
        "unused"
      ),
      document: "record",
      localization: Localization(preferredLanguages: ["en-US"]),
      file: "046d-c21d.plist"
    )
  }

  @Test
  func theBundledPersonaRulesNameThePersona() {
    #expect(
      Self.message("virtualDevice.bundledMissing", ["Generic"])
        == "046d-c21d.plist, persona: The bundled records must hold a record for the persona "
        + "Generic. Fix: Reinstall OpenJoystickDriver."
    )
    #expect(
      Self.message("virtualDevice.bundledPersona", ["Generic"])
        == "046d-c21d.plist, persona: A bundled record must define the persona Generic and hold "
        + "no match. Fix: Reinstall OpenJoystickDriver."
    )
  }

  @Test
  func aPackageFileOfTheWrongKindNamesTheListAndBothKinds() {
    #expect(
      Self.message("modPackage.kindMismatch", ["controllers", "patch", "record"])
        == "046d-c21d.plist, controllers: A patch file cannot be listed under controllers in "
        + "mod.plist, which lists record files. Fix: List the file under the list that matches "
        + "its kind."
    )
  }

  @Test
  func theIdentityRangeNamesBothIDs() {
    #expect(
      Self.message("record.identityRange")
        == "046d-c21d.plist, vendorID: A controller needs a vendorID of 1...65535 and a "
        + "productID of 0...65535. Fix: Set vendorID and productID inside those ranges."
    )
  }

  @Test
  func anUnsupportedUSBConfigurationNamesIt() {
    #expect(
      Self.message("deviceCatalog.usbConfiguration", ["Other"])
        == "046d-c21d.plist, usb.configuration: A USB configuration must be "
        + "SetConfiguration1BeforeClaim, not Other. Fix: Set configuration to "
        + "SetConfiguration1BeforeClaim, or leave it out."
    )
  }

  @Test
  func aMisplacedPatchNamesTheExpectedPath() {
    #expect(
      Self.message("patch.path", ["all/tuning.plist"])
        == "046d-c21d.plist, selector: A patch file must sit at all/tuning.plist. Fix: Move the "
        + "file there, or change its selector."
    )
  }

  @Test
  func aTuningDefaultsSelectorOtherThanAllNamesTheKey() {
    #expect(
      Self.message("tuningDefaults.selector")
        == "046d-c21d.plist, selector: The selector of the tuning defaults must be all. Fix: Set "
        + "selector to all."
    )
  }
}
