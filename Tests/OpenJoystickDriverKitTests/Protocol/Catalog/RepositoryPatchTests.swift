import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The members of the records that
/// ``RepositoryValidation/applyPatches(controllers:patches:output:)`` writes, and the patch files
/// it accepts.
@Suite
struct RepositoryPatchTests {
  private static func scratch(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("RepositoryValidationTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
  }

  private static func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try OrderedJSON.parse(Data(text.utf8)).plistData().write(to: url)
  }

  /// The canonical bytes of the record at `url`, which compare by content whatever the key order.
  private static func read(_ url: URL) throws -> Data {
    try DocumentCoder.write(
      DocumentCoder.read(Data(contentsOf: url), file: url.lastPathComponent)
    )
  }

  /// The canonical bytes of the JSON `text`.
  private static func dictionary(_ text: String) throws -> Data {
    try DocumentCoder.write(JSONSerialization.jsonObject(with: Data(text.utf8)))
  }

  // MARK: patches write members in the order of the record, then of the patches

  private static let record = """
    {
      "apiVersion": "openjoystickdriver/v1alpha3",
      "kind": "Controller",
      "vendorID": 1234,
      "productID": 5678,
      "usb": {
        "interface": 0,
        "endpoints": [1, 2, 3],
        "nested": {
          "m": 1
        }
      },
      "tuning": {
        "stickDeadzone": 0.1
      }
    }

    """

  private static let patch = """
    {
      "apiVersion": "openjoystickdriver/v1alpha3",
      "kind": "ControllerPatch",
      "selector": {"vendorID": 1234, "productID": 5678},
      "patch": {
        "server": "ojd",
        "usb": {
          "zeta": 1,
          "endpoints": [9, 8, 7, 6],
          "nested": {"z": 3, "a": 2},
          "alpha": {"y": 1, "x": 2}
        },
        "tuning": {"frameQueueCapacity": 4, "stickDeadzone": 0.2}
      }
    }
    """

  private static let secondPatch = """
    {
      "apiVersion": "openjoystickdriver/v1alpha3",
      "kind": "ControllerPatch",
      "selector": {"model": "04d2-162e"},
      "patch": {
        "usb": {"beta": true, "alpha": {"w": 0}},
        "route": "ojd"
      },
      "remove": ["usb.endpoints"]
    }
    """

  @Test
  func patchesAddMembersInPatchOrderAfterRecordsMembers() throws {
    try Self.scratch { directory in
      try Self.write(
        Self.record,
        to: directory.appendingPathComponent("records/04d2/04d2-162e.plist")
      )
      try Self.write(
        Self.patch,
        to: directory.appendingPathComponent("patches/04d2/04d2-162e.patch.plist")
      )
      try Self.write(
        Self.secondPatch,
        to: directory.appendingPathComponent("patches/model-04d2-162e.patch.plist")
      )
      let output = directory.appendingPathComponent("out")
      let problems = RepositoryValidation.applyPatches(
        controllers: directory.appendingPathComponent("records"),
        patches: directory.appendingPathComponent("patches"),
        output: output
      )
      #expect(problems.isEmpty, "\(problems)")
      // The array the first patch replaces is removed by the second patch; its other members
      // and the new members of both patches are present.
      #expect(
        try Self.read(output.appendingPathComponent("04d2/04d2-162e.plist"))
          == Self.dictionary(
            """
            {
              "apiVersion": "openjoystickdriver/v1alpha3",
              "kind": "Controller",
              "vendorID": 1234,
              "productID": 5678,
              "usb": {
                "interface": 0,
                "nested": {"m": 1, "z": 3, "a": 2},
                "alpha": {"y": 1, "x": 2, "w": 0},
                "beta": true,
                "zeta": 1
              },
              "tuning": {"stickDeadzone": 0.2, "frameQueueCapacity": 4},
              "server": "ojd",
              "route": "ojd"
            }
            """
          )
      )
    }
  }

  @Test
  func patchFileInDeeperDirectoryIsRefused() throws {
    try Self.scratch { directory in
      try Self.write(
        Self.record,
        to: directory.appendingPathComponent("records/04d2/04d2-162e.plist")
      )
      try Self.write(
        Self.patch,
        to: directory.appendingPathComponent("patches/04d2/deeper/04d2-162e.patch.plist")
      )
      let problems = RepositoryValidation.applyPatches(
        controllers: directory.appendingPathComponent("records"),
        patches: directory.appendingPathComponent("patches"),
        output: directory.appendingPathComponent("out")
      )
      #expect(problems.map(\.message).contains("the patch path must be 04d2/04d2-162e.patch.plist"))
      #expect(problems.allSatisfy { $0.code == .invalidControllerRecord })
    }
  }

  @Test
  func patchThatWritesSameNumberAnotherWayChangesNothing() throws {
    try Self.scratch { directory in
      try Self.write(
        Self.record,
        to: directory.appendingPathComponent("records/04d2/04d2-162e.plist")
      )
      let patch = """
        {
          "apiVersion": "openjoystickdriver/v1alpha3",
          "kind": "ControllerPatch",
          "selector": {"vendorID": 1234, "productID": 5678},
          "patch": {"usb": {"interface": 0.0}}
        }
        """
      try Self.write(
        patch,
        to: directory.appendingPathComponent("patches/04d2/04d2-162e.patch.plist")
      )
      let problems = RepositoryValidation.applyPatches(
        controllers: directory.appendingPathComponent("records"),
        patches: directory.appendingPathComponent("patches"),
        output: directory.appendingPathComponent("out")
      )
      let model = ControllerModelID(vendorID: 1234, productID: 5678)
      #expect(problems.map(\.message) == ["the patch changes nothing in \(model)"])
    }
  }
}
