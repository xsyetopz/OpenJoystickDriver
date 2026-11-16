import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct HIDUsageMapMessageTests {
  private static let english = Localization(preferredLanguages: ["en-US"])
  private static let usage = HIDUsage(usagePage: 1, usage: 48)

  private static func message(_ entries: [HIDUsageMap.Entry]) -> String? {
    do {
      _ = try HIDUsageMap(entries: entries)
      return nil
    } catch {
      return ControllerRecordSet.problemDescription(
        error,
        document: "record",
        localization: english,
        file: "046d-c21d.plist"
      )
    }
  }

  @Test
  func emptyMapNamesFileKeyPathRuleAndFix() {
    #expect(
      Self.message([])
        == "046d-c21d.plist, input.hidUsageMap.usages: A usage map must list at least one usage. "
        + "Fix: Add a usage, or delete hidUsageMap."
    )
  }

  @Test
  func repeatedUsageNamesUsage() {
    let entry = HIDUsageMap.Entry(usage: Self.usage, binding: .button(.south))
    #expect(
      Self.message([entry, entry])
        == "046d-c21d.plist, input.hidUsageMap.usages[]: Usage 1/48 is named twice, and only "
        + "entries for its two halves can share a usage. Fix: Name each usage once, or give the "
        + "entries the Positive and Negative halves."
    )
  }

  @Test
  func thresholdOutsideOpenIntervalNamesUsage() {
    let binding = HIDUsageMap.Binding.axisButton(
      .init(half: .positive, control: .east, threshold: 1.5)
    )
    #expect(
      Self.message([.init(usage: Self.usage, binding: binding)])
        == "046d-c21d.plist, input.hidUsageMap.usages[].threshold: The threshold of usage 1/48 "
        + "must be above 0 and below 1. Fix: Set threshold above 0 and below 1."
    )
  }

  @Test
  func decodedUsageMapProblemReadsInChosenLanguage() {
    let json = """
      {"usages": [
        {"kind": "Button", "page": 1, "usage": 48, "control": "South"},
        {"kind": "Button", "page": 1, "usage": 48, "control": "East"}
      ]}
      """
    do {
      _ = try JSONDecoder().decode(ControllerRecordDocument.UsageMap.self, from: Data(json.utf8))
      Issue.record("a usage named twice was accepted")
    } catch {
      #expect(
        ControllerRecordSet.problemDescription(
          error,
          document: "record",
          localization: Self.english,
          file: "046d-c21d.plist"
        ).hasPrefix("046d-c21d.plist, input.hidUsageMap.usages[]: Usage 1/48 is named twice")
      )
    }
  }
}
