import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct AccessValueSpellingTests {
  private static func decodes<Value: Decodable>(_ type: Value.Type, _ raw: String) -> Bool {
    (try? JSONDecoder().decode(type, from: Data("\"\(raw)\"".utf8))) != nil
  }

  @Test
  func scopesAreUpperCamelCaseAndCommandLineNamesAreKebabCase() {
    #expect(EndpointScope.allCases.map(\.rawValue) == ["Read", "Control"])
    #expect(EndpointScope.allCases.map(\.commandLineName) == ["read", "control"])
    #expect(CommandLineName.collisions(in: EndpointScope.self).isEmpty)
    for scope in EndpointScope.allCases {
      #expect(CommandLineName.value(of: scope.commandLineName) == scope)
    }
  }

  @Test(arguments: ["read", "control", "Reads", "READ", ""])
  func scopeRefusesAnyOtherSpelling(raw: String) {
    #expect(!Self.decodes(EndpointScope.self, raw))
    #expect(EndpointScope(rawValue: raw) == nil)
  }

  @Test
  func publisherKindsAndTransportsAreUpperCamelCase() {
    #expect(Self.decodes(CodeSigningIdentity.Kind.self, "Signed"))
    #expect(Self.decodes(CodeSigningIdentity.Kind.self, "Platform"))
    #expect(Self.decodes(CodeSigningIdentity.Kind.self, "AdHoc"))
    #expect(Self.decodes(AccessTransport.self, "Socket"))
    #expect(Self.decodes(AccessTransport.self, "Web"))
  }

  @Test(arguments: ["signed", "platform", "adHoc", "ad-hoc"])
  func publisherKindRefusesAnyOtherSpelling(raw: String) {
    #expect(!Self.decodes(CodeSigningIdentity.Kind.self, raw))
  }

  @Test(arguments: ["socket", "web"])
  func transportRefusesAnyOtherSpelling(raw: String) {
    #expect(!Self.decodes(AccessTransport.self, raw))
  }

  @Test
  func errorDomainsAreUpperCamelCaseWithUpperCaseAcronyms() {
    #expect(
      [ErrorCode.Domain.endpoint, .commandLine, .remapping, .mod, .document].map(\.rawValue)
        == ["Endpoint", "CLI", "Remapping", "Mod", "Document"]
    )
    for raw in ["endpoint", "cli", "remapping", "mod", "document", "Cli"] {
      #expect(ErrorCode.Domain(rawValue: raw) == nil, "\(raw)")
    }
  }

  @Test
  func virtualDeviceLayoutsAndLabelsRefuseTheirEarlierSpellings() {
    #expect(VirtualDeviceLayout(rawValue: "OJDGenericGamepad") == .ojdGenericGamepad)
    #expect(VirtualDeviceLayout(rawValue: "XboxOneGIP") == .xboxOneGIP)
    #expect(VirtualDeviceLayout(rawValue: "ojd-generic-gamepad") == nil)
    #expect(VirtualDeviceLayout(rawValue: "xbox-one-gip") == nil)
    #expect(VirtualDeviceLayout(rawValue: "XboxOneSBluetooth") == nil)
    #expect(VirtualIdentityGlyphFamily(rawValue: "Xbox") == .xbox)
    #expect(VirtualIdentityGlyphFamily(rawValue: "Generic") == .generic)
    #expect(VirtualIdentityGlyphFamily(rawValue: "xbox") == nil)
    #expect(VirtualIdentityGlyphFamily(rawValue: "generic") == nil)
  }

  @Test
  func acronymValuesSpellAcronymInUpperCase() {
    #expect(ControllerOwnershipObservation.extensionOwnedUSB.rawValue == "ExtensionOwnedUSB")
    #expect(ControllerOwnershipObservation.systemHIDVisible.rawValue == "SystemHIDVisible")
    #expect(DuplicateExposureRisk.systemHIDVisible.rawValue == "SystemHIDVisible")
    for raw in ["ExtensionOwnedUsb", "SystemHidVisible"] {
      #expect(ControllerOwnershipObservation(rawValue: raw) == nil, "\(raw)")
      #expect(DuplicateExposureRisk(rawValue: raw) == nil, "\(raw)")
    }
  }

  @Test
  func rumbleCommandKindsAreUpperCamelCase() {
    #expect(RumbleCommandLine.Kind.setRumble.rawValue == "SetRumble")
    #expect(RumbleCommandLine.Kind.stopRumble.rawValue == "StopRumble")
  }
}
