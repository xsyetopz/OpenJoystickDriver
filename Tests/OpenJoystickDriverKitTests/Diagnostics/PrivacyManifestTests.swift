import Foundation
import Testing

struct PrivacyManifestTests {
  private static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Diagnostics
    .deletingLastPathComponent()  // OpenJoystickDriverKitTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // repository root

  @Test
  func appManifestDeclaresNoTrackingAndOneDiagnosticDataType() throws {
    let url = Self.root.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/PrivacyInfo.xcprivacy"
    )
    let manifest = try #require(
      unsafe PropertyListSerialization.propertyList(
        from: Data(contentsOf: url),
        options: 0,
        format: nil
      ) as? [String: Any]
    )
    #expect(manifest["NSPrivacyTracking"] as? Bool == false)
    #expect((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
    let collected = try #require(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
    #expect(collected.count == 1)
    let entry = collected[0]
    #expect(
      entry["NSPrivacyCollectedDataType"] as? String
        == "NSPrivacyCollectedDataTypeOtherDiagnosticData"
    )
    #expect(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool == true)
    #expect(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool == false)
    #expect(
      entry["NSPrivacyCollectedDataTypePurposes"] as? [String] == [
        "NSPrivacyCollectedDataTypePurposeAppFunctionality"
      ]
    )
  }

  @Test
  func xcodeProjectCopiesTheManifestIntoTheAppResources() throws {
    let project = try String(
      contentsOf: Self.root.appendingPathComponent("OpenJoystickDriver.xcodeproj/project.pbxproj"),
      encoding: .utf8
    )
    #expect(project.contains("PrivacyInfo.xcprivacy in Resources"))
  }
}
