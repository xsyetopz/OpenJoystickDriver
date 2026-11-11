import Foundation
import OpenJoystickDriverKit

extension GenerateCommand {
  /// The checked documents that `script` returns.
  ///
  /// - Throws: ``CLIFailure`` when the script cannot be read, runs past the time limit, fails,
  ///   returns no document or a document that a reader refuses, or two documents name one file.
  static func documents(of script: String) async throws -> [GeneratedDocument] {
    guard FileManager.default.isReadableFile(atPath: script) else {
      throw CLIFailure(.fileAccessFailed, CLILocalized.format("cli.generate.group.unreadable", script))
    }
    let report = try await report(of: script)
    let text: String?
    switch report {
    case .missingGenerate:
      throw CLIFailure(.invalidInputFile, CLILocalized.format("cli.generate.group.missingGenerate", script))
    case .failure(let message, let line):
      throw CLIFailure(
        .invalidInputFile,
        line.map {
          CLILocalized.format("cli.generate.group.scriptFailedAtLine", script, String($0), message)
        } ?? CLILocalized.format("cli.generate.group.scriptFailed", script, message)
      )
    case .result(let json):
      text = json
    }
    let trees = try trees(of: text)
    var documents: [GeneratedDocument] = []
    for (index, tree) in trees.enumerated() {
      do { documents.append(try GeneratedDocumentChecker.check(tree)) } catch {
        throw CLIFailure(
          .invalidInputFile,
          CLILocalized.format(
            "cli.generate.group.documentInvalid",
            String(index + 1),
            "\(error)"
          )
        )
      }
    }
    var firstIndex: [String: Int] = [:]
    for (index, document) in documents.enumerated() {
      if let first = firstIndex[document.fileName] {
        throw CLIFailure(
          .invalidInputFile,
          CLILocalized.format(
            "cli.generate.group.duplicate",
            String(first + 1),
            String(index + 1),
            document.fileName
          )
        )
      }
      firstIndex[document.fileName] = index
    }
    return documents
  }

  /// The report that the helper process wrote for `script`.
  private static func report(of script: String) async throws -> GenerateReport {
    guard let helper else {
      throw CLIFailure(
        .launchFailed,
        CLILocalized.format("cli.generate.group.helperFailed", "no executable")
      )
    }
    let limit = CLIContext.current.timeout ?? defaultTimeout
    let outcome: GenerateRunner.Outcome
    do {
      outcome = try await GenerateRunner.run(
        executable: helper,
        script: URL(fileURLWithPath: script),
        timeout: limit
      )
    } catch {
      throw CLIFailure(
        .launchFailed,
        CLILocalized.format("cli.generate.group.helperFailed", error.localizedDescription)
      )
    }
    if outcome.timedOut {
      throw CLIFailure(
        .aborted,
        CLILocalized.format("cli.generate.group.timedOut", script, String(limit))
      )
    }
    guard let report = try? JSONDecoder().decode(GenerateReport.self, from: outcome.output) else {
      throw CLIFailure(
        .launchFailed,
        CLILocalized.format("cli.generate.group.helperFailed", "exit status \(outcome.status)")
      )
    }
    return report
  }

  /// The documents in the JSON text of the result: one dictionary, or a list of them.
  ///
  /// - Throws: ``CLIFailure`` for `null`, no value, a value that is not a dictionary, an empty
  ///   list, and a list with an item that is not a dictionary.
  private static func trees(of text: String?) throws -> [[String: Any]] {
    let refusal = CLIFailure(.invalidInputFile, CLILocalized.text("cli.generate.group.notDocuments"))
    guard let text,
      let value = try? JSONSerialization.jsonObject(
        with: Data(text.utf8),
        options: .fragmentsAllowed
      )
    else { throw refusal }
    if let tree = value as? [String: Any] { return [tree] }
    guard let list = value as? [Any], !list.isEmpty else { throw refusal }
    return try list.map { item in
      guard let tree = item as? [String: Any] else { throw refusal }
      return tree
    }
  }
}
