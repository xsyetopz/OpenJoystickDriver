import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// What `ojd config set` and `ojd config unset` share: they set or remove one tuning key in the
/// user's patch of a controller model, or in `all.patch.json`, and print the same result.
enum ConfigChange {
  /// The `--json` result. `value` is absent for `unset`, and `previous` while no layer set the key.
  struct Result: Encodable, Equatable {
    /// The tuning key.
    let key: String
    /// The number that `set` writes, or nil for `unset`.
    let value: Double?
    /// The number the user's record held before, or nil when no layer set the key.
    let previous: Double?
    /// The controller model as `VVVV:PPPP`, or nil for `all.patch.json`.
    let controller: String?
    /// The path of the file that the command writes.
    let file: String
    /// Whether the file did not exist before.
    let created: Bool
    /// Whether the change removes the file because it holds nothing else.
    let removesFile: Bool
  }

  /// The tuning key named `name`.
  ///
  /// - Throws: `ValidationError` when `name` is not a tuning key.
  static func key(_ name: String) throws -> ControllerTuning.Key {
    guard let key = ControllerTuning.Key(rawValue: name) else {
      throw ValidationError(
        CLILocalized.format(
          "cli.config.group.unknownKey",
          name,
          ControllerTuning.Key.allCases.map(\.rawValue).joined(separator: ", ")
        )
      )
    }
    return key
  }

  /// The number written as `text`: digits with an optional `-` and one `.`.
  ///
  /// Hexadecimal floats, exponents, `nan` and `inf` are not numbers here.
  ///
  /// - Throws: `ValidationError` when `text` is not such a number.
  static func number(_ text: String) throws -> Double {
    let digits = text.hasPrefix("-") ? text.dropFirst() : Substring(text)
    let isDecimal =
      digits.contains { $0 != "." } && digits.filter { $0 == "." }.count <= 1
      && digits.allSatisfy { $0 == "." || ("0"..."9").contains($0) }
    guard isDecimal, let number = Double(text), number.isFinite else {
      throw ValidationError(CLILocalized.format("cli.config.group.notNumber", text))
    }
    return number
  }

  /// The edit that `KEY` and `VALUE` name; a nil `value` removes the key.
  ///
  /// - Throws: `ValidationError` when the key or the number is not valid.
  static func edit(key name: String, value: String?) throws -> ControllerRecordWriter.TuningEdit {
    let key = try key(name)
    guard let value else { return .remove(key) }
    return .set(key, try number(value))
  }

  /// Applies `edit` to the record of `model`, or to `all.patch.json` without a model, and prints
  /// the result.
  ///
  /// - Throws: ``CLIFailure`` when the model has no record, the file or the result is not valid, an
  ///   `unset` key is not set, or the file cannot be written.
  static func run(
    _ edit: ControllerRecordWriter.TuningEdit,
    controller model: ControllerModelID?,
    global: GlobalOptions
  ) async throws {
    try await global.run {
      let target = model.map(ControllerRecordWriter.Target.model) ?? .allControllers
      let change = try change(edit, for: target)
      try write(change)
      var value: Double?
      if case .set(_, let number) = edit { value = number }
      let result = Result(
        key: edit.key.rawValue,
        value: value,
        previous: change.previousTuning,
        controller: model?.description,
        file: change.file.path,
        created: change.created,
        removesFile: change.data == nil
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain:
        CLIOutput.plain([
          [result.key] + [result.value.map(ConfigShowCommand.text)].compactMap { $0 }
            + [result.file]
        ])
      case .human: printHuman(result)
      }
    }
  }

  /// Prints the success message on stderr for `set` or `unset`.
  private static func printHuman(_ result: Result) {
    CLIOutput.success(
      result.value.map {
        CLILocalized.format(
          "cli.config.set.success",
          result.key,
          ConfigShowCommand.text($0),
          result.file
        )
      } ?? CLILocalized.format("cli.config.unset.success", result.key, result.file)
    )
  }

  /// The change that `edit` makes to the file for `target`, before it is written.
  ///
  /// - Throws: ``CLIFailure`` with `notFound`, `invalidInputFile` or `usage` when the writer
  ///   refuses the edit.
  private static func change(
    _ edit: ControllerRecordWriter.TuningEdit,
    for target: ControllerRecordWriter.Target
  ) throws -> ControllerRecordWriter.Change {
    do {
      return try ControllerRecordWriter.change(
        edit,
        for: target,
        records: RecordStore.load(),
        directory: RecordStore.directory
      )
    } catch {
      switch error {
      case .refused(.noRecord(let model)):
        let identity = model.description
        throw CLIFailure(
          .notFound,
          CLILocalized.format("cli.config.group.noRecord", identity, identity)
        )
      case .refused(.invalidFile(let problem)):
        throw CLIFailure(
          .invalidInputFile,
          CLILocalized.format("cli.config.group.invalid", edit.key.rawValue, problem)
        )
      case .refused(.invalidResult(let problem)):
        throw CLIFailure(
          .usage,
          CLILocalized.format("cli.config.group.invalid", edit.key.rawValue, problem)
        )
      case .notSet(let key):
        throw CLIFailure(
          .notFound,
          CLILocalized.format("cli.config.unset.notSet", key.rawValue)
        )
      }
    }
  }

  /// Writes `change` to disk.
  ///
  /// - Throws: ``CLIFailure`` with `fileAccessFailed` when the file cannot be written.
  private static func write(_ change: ControllerRecordWriter.Change) throws {
    do { try ControllerRecordWriter.write(change) } catch {
      throw CLIFailure(
        .fileAccessFailed,
        CLILocalized.format(
          "cli.record.install.failed",
          change.file.path,
          error.localizedDescription
        )
      )
    }
  }
}
