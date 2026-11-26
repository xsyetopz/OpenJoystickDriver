import Foundation
import Testing

@testable import OpenJoystickDriverKit

// The tests use fixture documents and never load the bundled catalog.
struct ControllerPatchParseOrderTests {
  private static let identity = ControllerModelID(vendorID: 0x1234, productID: 0xABCD)

  private static func key(_ document: [String: Any]) -> String? {
    do {
      _ = try ControllerPatch.parse(OrderedJSON(foundation: document))
      return nil
    } catch { return (error as? ControllerRecordProblem)?.key }
  }

  private static func document(
    selector: ControllerPatch.Selector = .identity(identity),
    patch: [String: Any] = [:],
    remove: [String] = []
  ) -> [String: Any] {
    ControllerPatch.document(selector: selector, body: patch, remove: remove)
  }

  @Test
  func badPatchSectionWinsOverBadRemove() {
    let document = Self.document(patch: ["bogus": 1], remove: ["bogus"])
    #expect(Self.key(document) == "error.E5007.patch.patchSections")
  }

  @Test
  func badSelectorWinsOverBadPatch() {
    var document = Self.document(patch: ["bogus": 1])
    document["selector"] = ["all": false]
    #expect(Self.key(document) == "error.E5007.patch.selectorAllTrue")
  }

  @Test
  func badModeEntryWinsOverAllScope() {
    let document = Self.document(selector: .all, patch: ["modes": [["bogus": 1]]])
    #expect(Self.key(document) == "error.E5007.patch.patchModeEntries")
  }

  @Test
  func allPatchScopeWinsOverBadRemove() {
    let document = Self.document(selector: .all, patch: ["name": "x"], remove: ["bogus"])
    #expect(Self.key(document) == "error.E5007.patch.patchAllOnlyTuning")
  }

  @Test
  func unitPatchWithRemoveRefusedBeforeRemoveIsRead() throws {
    let unit = try #require(ControllerPortKey(rawValue: "U-AAAAAAAAAAAAAAAA"))
    let document = Self.document(
      selector: .unit(Self.identity, unit),
      patch: ["tuning": ["stickDeadzone": 0.1]],
      remove: ["bogus"]
    )
    #expect(Self.key(document) == "error.E5007.patch.patchUnitOnlyCalibration")
  }

  @Test
  func unitPatchWithoutPatchRefused() throws {
    let unit = try #require(ControllerPortKey(rawValue: "U-AAAAAAAAAAAAAAAA"))
    let document = Self.document(selector: .unit(Self.identity, unit), remove: ["usb"])
    #expect(Self.key(document) == "error.E5007.patch.patchUnitOnlyCalibration")
  }
}
