import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd record test` command: replays captured reports through a model's record and compares
/// the parsed controller state with the expected state.
///
/// It needs no service.
struct RecordTestCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "test",
    abstract: CLILocalized.text("cli.record.test.abstract"),
    discussion: CLILocalized.text("cli.record.test.discussion")
  )

  /// The `--json` result. `differences` is empty when the states match.
  struct Result: Encodable, Equatable {
    /// One field of the controller state that differs; `expected` and `actual` are its JSON.
    struct Difference: Encodable, Equatable {
      /// The field of the controller state.
      let field: String
      /// The expected value as JSON.
      let expected: String
      /// The parsed value as JSON.
      let actual: String
    }

    /// The controller model as `VVVV:PPPP`.
    let identity: String
    /// Whether the parsed state matches the expected state.
    let matches: Bool
    /// The number of received packets that were replayed.
    let inputReports: Int
    /// The fields that differ.
    let differences: [Difference]
  }

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The model whose record parses the packets.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.record.group.identity"),
      valueName: "VVVV:PPPP"
    )
  )
  var model: ControllerModelID

  /// `--packets`: the capture file, with the lines that `ojd controller capture --json` prints.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.record.test.packets"),
      valueName: "CAPTURE"
    )
  )
  var packets: String

  /// `--expect`: the JSON file with the expected controller state.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.record.test.expect"),
      valueName: "STATE"
    )
  )
  var expect: String

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let set = RecordStore.load()
      RecordStore.warn(set.problems.filter { $0.model == model })
      guard let record = set.records[model] else {
        throw CLIFailure(
          .notFound,
          CLILocalized.format("cli.record.show.notFound", model.description)
        )
      }
      let outcome = try test(
        record,
        capture: RecordStore.read(packets),
        expectation: RecordStore.read(expect)
      )
      let result = Result(
        identity: model.description,
        matches: outcome.matches,
        inputReports: outcome.inputReports,
        differences: outcome.differences.map {
          Result.Difference(field: $0.field, expected: $0.expected, actual: $0.actual)
        }
      )
      try print(result)
      if !outcome.matches {
        throw CLIFailure(
          .recordTestMismatch,
          CLILocalized.plural(
            "cli.record.test.mismatch",
            model.description,
            expect,
            outcome.differences.count
          )
        )
      }
    }
  }

  /// Replays `capture` through `record` and compares the parsed state with `expectation`.
  ///
  /// - Throws: ``CLIFailure`` with `invalidInputFile` when the capture or the expectation is not
  ///   usable.
  private func test(
    _ record: ControllerRecord,
    capture: Data,
    expectation: Data
  ) throws -> ControllerRecordTestResult {
    do { return try record.test(capture: capture, expectation: expectation) } catch let error
      as ControllerRecordTestError
    {
      throw CLIFailure(
        .invalidInputFile,
        error.message(model: model, capture: packets, expectation: expect)
      )
    }
  }

  /// Prints `result` as JSON, as `--plain` rows of the differences, or as text.
  private func print(_ result: Result) throws {
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(result)
    case .plain: CLIOutput.plain(result.differences.map { [$0.field, $0.expected, $0.actual] })
    case .human:
      if result.matches {
        CLIOutput.success(
          CLILocalized.plural("cli.record.test.matched", result.identity, result.inputReports)
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
