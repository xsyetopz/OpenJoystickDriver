import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The `ControllerPatch` cases in `Tests/RepositoryScripts/fixtures/controller_patch/cases.json`
/// and the rules of the ``OrderedJSON`` merge.
struct ControllerPatchMergeTests {
  private static let cases = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Catalog
    .deletingLastPathComponent()  // Protocol
    .deletingLastPathComponent()  // OpenJoystickDriverKitTests
    .deletingLastPathComponent()  // Tests
    .appendingPathComponent("RepositoryScripts/fixtures/controller_patch/cases.json")

  private static func fixture() throws -> [String: Any] {
    try #require(
      try JSONSerialization.jsonObject(with: Data(contentsOf: cases)) as? [String: Any]
    )
  }

  private static func json(_ text: String) throws -> OrderedJSON {
    try OrderedJSON.parse(Data(text.utf8))
  }

  /// The patches of one layer.
  ///
  /// An item is a patch document, or `{"owner", "document"}` to name the package that holds it.
  private static func entries(
    _ value: Any?,
    file: String
  ) throws -> [(patch: ControllerPatch, owner: String?)] {
    try (value as? [[String: Any]] ?? []).map { item in
      let owner = item["owner"] as? String
      let document = item["document"] as? [String: Any] ?? item
      return (try ControllerPatch.parse(OrderedJSON(foundation: document), file: file), owner)
    }
  }

  @Test
  func everyCaseGivesItsEffectiveRecord() throws {
    let cases = try #require(try Self.fixture()["cases"] as? [[String: Any]])
    #expect(cases.count >= 10)
    for fixture in cases {
      let name = try #require(fixture["name"] as? String)
      let record = try #require(fixture["record"] as? [String: Any])
      let expected = try #require(fixture["expected"] as? [String: Any])
      let effective = ControllerPatchMerge.effective(
        record: try OrderedJSON(foundation: record),
        builtin: try Self.entries(fixture["builtin"], file: name).map(\.patch),
        package: try Self.entries(fixture["package"], file: name),
        user: try Self.entries(fixture["user"], file: name).map(\.patch)
      )
      #expect(effective.hasSameValue(as: try OrderedJSON(foundation: expected)), "\(name)")
    }
  }

  @Test
  func rejectedDocumentsAreRefused() throws {
    let rejected = try #require(try Self.fixture()["rejected"] as? [[String: Any]])
    #expect(!rejected.isEmpty)
    for fixture in rejected {
      let name = try #require(fixture["name"] as? String)
      let document = try #require(fixture["document"] as? [String: Any])
      do {
        _ = try ControllerPatch.parse(OrderedJSON(foundation: document))
        Issue.record("\(name) was accepted")
      } catch {
        let code = ControllerRecordSet.problemCode(error)?.rawValue
        #expect(code == fixture["code"] as? String, "\(name)")
        #expect(
          ControllerRecordSet.problemDescription(error, document: "record") == fixture["message"]
            as? String,
          "\(name)"
        )
      }
    }
  }

  @Test
  func theCasesCoverTheRequiredBehaviour() throws {
    let cases = try #require(try Self.fixture()["cases"] as? [[String: Any]])
    let names = Set(cases.compactMap { $0["name"] as? String })
    #expect(names.contains("null deletes a parameter"))
    #expect(names.contains("a user patch beats a package patch"))
  }

  @Test
  func selectorsOrderAllThenIdentityThenModel() throws {
    let identity = ControllerModelID(vendorID: 0x045E, productID: 0x02EA)
    let patches = [
      ControllerPatch(
        selector: .identity(identity),
        body: try Self.json(#"{"ownership": "ojd"}"#)
      ),
      ControllerPatch(selector: .all, body: try Self.json(#"{"tuning": {}}"#)),
      ControllerPatch(
        selector: .model("045e-02ea"),
        body: try Self.json(#"{"ownership": "macos"}"#)
      ),
    ]
    #expect(ControllerPatchMerge.ordered(patches).map(\.selector.rank) == [0, 1, 2])
  }

  @Test
  func mergingAPatchOrdersTheRecordFirstThenThePatchsNewMembers() throws {
    let record = try Self.json(#"{"b": {"y": 1, "x": 2}, "a": [1, 2], "c": 3}"#)
    let patch = try Self.json(
      #"{"d": {"q": 1, "p": null}, "b": {"z": 1, "x": 5}, "a": [{"k": 1, "j": 2}], "c": null}"#
    )
    let merged = ControllerPatchMerge.mergePatch(record, patch)
    #expect(
      try Self.json(#"{"b": {"y": 1, "x": 5, "z": 1}, "a": [{"k": 1, "j": 2}], "d": {"q": 1}}"#)
        == merged
    )
    // A member deleted and added again, and an object over a scalar, take the patch's order.
    let again = ControllerPatchMerge.mergePatch(
      ControllerPatchMerge.mergePatch(merged, try Self.json(#"{"b": null}"#)),
      try Self.json(#"{"b": {"w": 1, "v": 2}, "d": {"s": 0}}"#)
    )
    #expect(
      try Self.json(#"{"a": [{"k": 1, "j": 2}], "d": {"q": 1, "s": 0}, "b": {"w": 1, "v": 2}}"#)
        == again
    )
  }

  @Test
  func aMergedNumberKeepsItsText() throws {
    let record = try Self.json(#"{"tuning": {"stickDeadzone": 0.10, "keep": 100.50}}"#)
    let digits = "1234567890123456789012345"
    let patch = try Self.json(
      #"{"tuning": {"stickDeadzone": 8E-2, "usbTransferTimeoutMs": 1e3, "big": "#
        + digits + "}}"
    )
    let merged = ControllerPatchMerge.mergePatch(record, patch)
    let expected = try Self.json(
      #"{"tuning": {"stickDeadzone": 8E-2, "keep": 100.50, "usbTransferTimeoutMs": 1e3, "#
        + #""big": "# + digits + "}}"
    )
    #expect(merged == expected)
    for text in ["8E-2", "1e3", "100.50", digits] {
      #expect(merged.compact().contains(text), "\(text)")
    }
  }

  @Test
  func numbersThatReadAsTheSameValueAreNotAChange() throws {
    let record = try Self.json(#"{"a": 1, "b": 0.08, "c": [1000]}"#)
    let same = try Self.json(#"{"c": [1e3], "b": 8E-2, "a": 1.0}"#)
    #expect(record.hasSameValue(as: same))
    #expect(!record.hasSameValue(as: try Self.json(#"{"a": 1, "b": 0.08, "c": [1001]}"#)))
    #expect(!record.hasSameValue(as: try Self.json(#"{"a": 1, "b": 0.08}"#)))
  }

  /// A number is compared by its digits and exponent, not through a type with a digit limit.
  @Test
  func longNumbersAreComparedByAllTheirDigits() throws {
    let same = [("100.50", "1.005E2"), ("-0", "0"), ("1e3", "1000"), ("1e400", "10E399")]
    for (left, right) in same {
      #expect(try Self.json(left).hasSameValue(as: Self.json(right)), "\(left) \(right)")
    }
    let forty = "123456789012345678901234567890123456789"
    let different = [(forty + "0", forty + "1"), ("1e400", "1e401"), ("0.08", "-0.08")]
    for (left, right) in different {
      #expect(try !Self.json(left).hasSameValue(as: Self.json(right)), "\(left) \(right)")
    }
  }
}
