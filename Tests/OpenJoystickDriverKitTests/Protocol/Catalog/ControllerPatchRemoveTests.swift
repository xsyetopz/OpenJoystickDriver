import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The `remove` list of a `ControllerPatch`: dotted key paths applied before `patch`. The tests
/// use fixture records and documents and never load the bundled catalog.
struct ControllerPatchRemoveTests {
  private static let identity = ControllerModelID(vendorID: 0x1234, productID: 0xABCD)

  private static func json(_ text: String) throws -> OrderedJSON {
    try OrderedJSON.parse(Data(text.utf8))
  }

  private static func document(
    remove: [String]? = nil,
    patch: [String: Any]? = nil,
    selector: ControllerPatch.Selector = .identity(identity)
  ) -> [String: Any] {
    var document = ControllerPatch.document(selector: selector, body: patch ?? [:])
    if let remove { document["remove"] = remove }
    return document
  }

  private static func parse(
    remove: [String]? = nil,
    patch: [String: Any]? = nil,
    selector: ControllerPatch.Selector = .identity(identity)
  ) throws -> ControllerPatch {
    try ControllerPatch.parse(
      OrderedJSON(foundation: document(remove: remove, patch: patch, selector: selector))
    )
  }

  private static func refusal(_ document: [String: Any]) -> ControllerRecordProblem? {
    do {
      _ = try ControllerPatch.parse(OrderedJSON(foundation: document))
      return nil
    } catch { return error as? ControllerRecordProblem }
  }

  private static let record = #"""
    {"vendorID": 4660, "productID": 43981,
     "usb": {"interface": 0, "configuration": "SetConfiguration1BeforeClaim"},
     "input": {"hidUsageMap": {"reportID": 1, "usages": [1, 2]}},
     "tuning": {"stickDeadzone": 0.1, "frameQueueCapacity": 4}}
    """#

  @Test
  func aRemovedKeyIsGone() throws {
    let patch = try Self.parse(remove: ["usb.configuration"])
    let result = ControllerPatchMerge.apply(patch, to: try Self.json(Self.record))
    let expected = try Self.json(
      #"""
      {"vendorID": 4660, "productID": 43981, "usb": {"interface": 0},
       "input": {"hidUsageMap": {"reportID": 1, "usages": [1, 2]}},
       "tuning": {"stickDeadzone": 0.1, "frameQueueCapacity": 4}}
      """#
    )
    #expect(result == expected)
  }

  @Test
  func aRemovedSectionIsGone() throws {
    let patch = try Self.parse(remove: ["input"])
    let result = ControllerPatchMerge.apply(patch, to: try Self.json(Self.record))
    #expect(result["input"] == nil)
    #expect(result["usb"] != nil)
  }

  @Test
  func aNestedDottedPathRemovesOnlyItsKey() throws {
    let patch = try Self.parse(remove: ["input.hidUsageMap.usages"])
    let result = ControllerPatchMerge.apply(patch, to: try Self.json(Self.record))
    #expect(result["input"] == (try Self.json(#"{"hidUsageMap": {"reportID": 1}}"#)))
  }

  @Test
  func aPathTheRecordLacksChangesNothing() throws {
    let record = try Self.json(Self.record)
    let patch = try Self.parse(remove: ["bluetoothLE.name", "usb.interface.deeper", "server"])
    #expect(ControllerPatchMerge.apply(patch, to: record) == record)
  }

  @Test
  func removeAppliesBeforePatch() throws {
    let patch = try Self.parse(remove: ["usb"], patch: ["usb": ["interface": 3]])
    let result = ControllerPatchMerge.apply(patch, to: try Self.json(Self.record))
    // Removed after the merge, `usb` would be gone; applied before it, only the patch's key stays.
    #expect(result["usb"] == (try Self.json(#"{"interface": 3}"#)))
  }

  @Test
  func aPatchThatOnlyRemovesIsAValidFile() throws {
    let patch = try Self.parse(remove: ["tuning.stickDeadzone"])
    #expect(patch.remove == [["tuning", "stickDeadzone"]])
    #expect(patch.body.members?.isEmpty == true)
  }

  @Test
  func aPathOutsideTheRecordSchemaIsRefusedByName() throws {
    let paths = [
      "bogus", "bogus.key", "tuning.bogus", "usb..interface", ".usb", "usb.", "",
      "apiVersion", "vendorID",
    ]
    for path in paths {
      let problem = try #require(Self.refusal(Self.document(remove: [path])), "\(path)")
      #expect(problem.code == .invalidControllerRecord, "\(path)")
      #expect(problem.description == "remove path \(path) is not in the record schema", "\(path)")
    }
  }

  @Test
  func aMalformedRemoveListIsRefused() throws {
    let duplicate = try #require(Self.refusal(Self.document(remove: ["usb", "usb"])))
    #expect(duplicate.description == "remove path usb is listed twice")
    #expect(Self.refusal(Self.document(remove: [])) != nil)
    var notText = Self.document(remove: ["usb"])
    notText["remove"] = [1]
    #expect(Self.refusal(notText) != nil)
    var neither = Self.document()
    neither["patch"] = nil
    #expect(Self.refusal(neither) != nil)
  }

  @Test
  func anAllPatchRefusesARemoveOutsideTuningKeys() throws {
    for path in ["usb", "tuning", "usb.interface"] {
      let problem = try #require(
        Self.refusal(Self.document(remove: [path], selector: .all)),
        "\(path)"
      )
      #expect(problem.code == .invalidControllerRecord, "\(path)")
    }
  }
}
