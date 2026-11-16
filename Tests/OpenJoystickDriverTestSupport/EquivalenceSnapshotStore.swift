package import Foundation

/// Reads and writes the equivalence snapshots in `Tests/EquivalenceSnapshots`.
///
/// A `.txt` snapshot is a text file of sections, each starting with a `## <record>` line, so a
/// comparison can name the records that changed; a `.json` snapshot is one JSON document, which
/// the comparison diffs by line. Biome skips `Tests/EquivalenceSnapshots`, because each file holds
/// the exact bytes a test renders. Modes, chosen by environment variable:
/// - default: compare the rendered text with the file and report a mismatch;
/// - `OJD_SNAPSHOT_WRITE=1`: rewrite the file from the current tree;
/// - `OJD_SNAPSHOT_ACTUAL_DIR=<dir>`: write the rendered text to `<dir>` and never fail, so
///   `just snapshots-check` can print the per-record diff.
package enum EquivalenceSnapshotStore {
  package static let directory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // OpenJoystickDriverTestSupport
    .deletingLastPathComponent()  // Tests
    .appendingPathComponent("EquivalenceSnapshots", isDirectory: true)

  /// `vvvv:pppp` in upper-case hexadecimal, the section title of a record.
  package static func recordTitle(vendorID: UInt16, productID: UInt16) -> String {
    func hex(_ value: UInt16) -> String {
      let digits = String(value, radix: 16, uppercase: true)
      return String(repeating: "0", count: 4 - digits.count) + digits
    }
    return "\(hex(vendorID)):\(hex(productID))"
  }

  /// Renders sections as `## title` followed by their lines, sorted by title, after `header`
  /// (`# ` comment lines and a blank line, which the comparison script ignores).
  package static func render(
    _ sections: [(title: String, lines: [String])],
    header: String = ""
  ) -> String {
    header
      + sections.sorted { $0.title < $1.title }
      .map { "## \($0.title)\n" + $0.lines.map { $0 + "\n" }.joined() }
      .joined(separator: "\n")
  }

  /// Returns nil when the snapshot matches or was written; otherwise a message for the failure.
  package static func verify(_ rendered: String, named name: String) throws -> String? {
    try verify(
      rendered,
      named: name,
      in: directory,
      environment: ProcessInfo.processInfo.environment
    )
  }

  /// `verify(_:named:)` against an explicit snapshot directory and environment.
  package static func verify(
    _ rendered: String,
    named name: String,
    in directory: URL,
    environment: [String: String]
  ) throws -> String? {
    let file = directory.appendingPathComponent(name)
    if let actual = environment["OJD_SNAPSHOT_ACTUAL_DIR"] {
      let target = URL(fileURLWithPath: actual, isDirectory: true)
      try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
      try Data(rendered.utf8).write(to: target.appendingPathComponent(name))
      return nil
    }
    if environment["OJD_SNAPSHOT_WRITE"] == "1" {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try Data(rendered.utf8).write(to: file)
      return nil
    }
    guard let expected = try? String(contentsOf: file, encoding: .utf8) else {
      return "\(name) is missing; run just snapshots-write"
    }
    return expected == rendered
      ? nil : "\(name) differs from the tree; run just snapshots-check for the diff"
  }
}
