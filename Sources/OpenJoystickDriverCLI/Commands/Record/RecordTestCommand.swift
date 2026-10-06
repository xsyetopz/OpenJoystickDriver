import ArgumentParser
import Foundation
import OpenJoystickDriverKit

extension PacketLogEntry {
  /// The packet's bytes, from its `hex` string.
  var reportBytes: [UInt8] { hex.split(separator: " ").compactMap { UInt8($0, radix: 16) } }
}

struct RecordTestCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "test",
    abstract: CLILocalized.text("cli.record.test.abstract"),
    discussion: CLILocalized.text("cli.record.test.discussion")
  )

  /// The `--json` result. `differences` is empty when the states match.
  struct Result: Encodable, Equatable {
    /// One field of the controller state that differs; `expected` and `actual` are its JSON.
    struct Difference: Encodable, Equatable {
      let field: String
      let expected: String
      let actual: String
    }

    let identity: String
    let matches: Bool
    let inputReports: Int
    let differences: [Difference]
  }

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.record.identity"),
      valueName: "VVVV:PPPP"
    )
  )
  var identity: RecordIdentity

  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.record.test.packets"),
      valueName: "CAPTURE"
    )
  )
  var packets: String

  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.record.test.expect"),
      valueName: "STATE"
    )
  )
  var expect: String

  func run() async throws {
    try await global.run {
      let set = RecordStore.load()
      RecordStore.warn(set.problems.filter { $0.identity == identity.identity })
      guard let record = set.records[identity.identity] else {
        throw CLIFailure(
          .notFound,
          CLILocalized.format("cli.record.show.not_found", identity.text)
        )
      }
      let reports = try Self.receivedReports(in: RecordStore.read(packets), path: packets)
      let expected = try Self.expectedState(in: RecordStore.read(expect), path: expect)
      let replay = try replay(record, reports: reports)
      let differences = try Self.differences(expected: expected, actual: replay.state)
      let result = Result(
        identity: identity.text,
        matches: differences.isEmpty,
        inputReports: replay.inputReports,
        differences: differences
      )
      try print(result)
      if !differences.isEmpty {
        throw CLIFailure(
          .recordTestMismatch,
          CLILocalized.format(
            "cli.record.test.mismatch",
            identity.text,
            expect,
            differences.count
          )
        )
      }
    }
  }

  private func replay(
    _ record: ControllerRecord,
    reports: [[UInt8]]
  ) throws -> ControllerRecordReplay {
    do {
      return try record.replay(reports: reports)
    } catch let error as ControllerRecordReplayError {
      switch error {
      case .noParser:
        throw CLIFailure(
          .invalidInputFile,
          CLILocalized.format("cli.record.test.no_parser", identity.text)
        )
      case .invalidReport(let index):
        throw CLIFailure(
          .invalidInputFile,
          CLILocalized.format("cli.record.test.parse_failed", identity.text, index + 1, packets)
        )
      case .noInput:
        throw CLIFailure(
          .invalidInputFile,
          CLILocalized.format("cli.record.test.no_input", packets, identity.text)
        )
      }
    }
  }

  /// The received packets of a capture, in order.
  /// The capture holds one `PacketLogEntry` JSON object per line,
  /// as `ojd controller capture --json` prints them.
  static func receivedReports(in data: Data, path: String) throws -> [[UInt8]] {
    var reports: [[UInt8]] = []
    guard let text = String(bytes: data, encoding: .utf8) else {
      throw invalidCapture(path, line: 1, "not UTF-8 text")
    }
    let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    for (offset, line) in lines.enumerated() where !line.allSatisfy(\.isWhitespace) {
      let entry: PacketLogEntry
      do { entry = try JSONDecoder().decode(PacketLogEntry.self, from: Data(line.utf8)) } catch {
        throw invalidCapture(path, line: offset + 1, error.localizedDescription)
      }
      guard entry.reportBytes.count == entry.length else {
        throw invalidCapture(path, line: offset + 1, "length does not match hex")
      }
      if entry.direction == .received { reports.append(entry.reportBytes) }
    }
    return reports
  }

  private static func invalidCapture(_ path: String, line: Int, _ problem: String) -> CLIFailure {
    CLIFailure(
      .invalidInputFile,
      CLILocalized.format("cli.record.test.capture_invalid", path, "line \(line): \(problem)")
    )
  }

  static func expectedState(in data: Data, path: String) throws -> ControllerState {
    do { return try JSONDecoder().decode(ControllerState.self, from: data) } catch {
      throw CLIFailure(
        .invalidInputFile,
        CLILocalized.format("cli.record.test.expect_invalid", path, "\(error)")
      )
    }
  }

  /// The fields of the state that differ, by name.
  /// `connection` is skipped: the service stamps it, and no parser sets it.
  static func differences(
    expected: ControllerState,
    actual: ControllerState
  ) throws -> [Result.Difference] {
    let expectedFields = try fields(expected)
    let actualFields = try fields(actual)
    return expectedFields.keys.sorted().compactMap { field in
      guard field != "connection", expectedFields[field] != actualFields[field] else { return nil }
      return Result.Difference(
        field: field,
        expected: expectedFields[field] ?? "",
        actual: actualFields[field] ?? ""
      )
    }
  }

  /// Each top-level field of the state's JSON, rendered with sorted keys.
  private static func fields(_ state: ControllerState) throws -> [String: String] {
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state))
    return try (object as? [String: Any] ?? [:]).mapValues {
      let data = try JSONSerialization.data(
        withJSONObject: $0,
        options: [.sortedKeys, .fragmentsAllowed]
      )
      return String(bytes: data, encoding: .utf8) ?? ""
    }
  }

  private func print(_ result: Result) throws {
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(result)
    case .plain: CLIOutput.plain(result.differences.map { [$0.field, $0.expected, $0.actual] })
    case .human:
      if result.matches {
        CLIOutput.success(
          CLILocalized.format("cli.record.test.matched", result.identity, result.inputReports)
        )
      }
      for difference in result.differences {
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.record.test.difference",
            difference.field,
            difference.expected,
            difference.actual
          )
        )
      }
    }
  }
}
