import Foundation
import OpenJoystickDriverKit

extension GenerateCommand {
  /// What happened to one generated document.
  struct Entry: Encodable {
    /// What the command did with the file.
    enum Status: String, Encodable {
      /// The file did not exist and the command wrote it.
      case created = "Created"
      /// The file held other content and the command replaced it.
      case replaced = "Replaced"
      /// The file already held the document.
      case unchanged = "Unchanged"
      /// There is no output folder; the command printed the document.
      case notWritten = "NotWritten"
    }

    /// The name of the file of the document.
    let file: String
    /// The `kind` of the document.
    let kind: String
    /// What the command did with the file.
    let status: Status
    /// The document as an XML property list, when the command wrote no file.
    let document: String?

    /// An entry of `document`.
    init(document: GeneratedDocument, status: Status) {
      file = document.fileName
      kind = document.kind
      self.status = status
      self.document = status == .notWritten ? String(decoding: document.data, as: UTF8.self) : nil
    }

    /// The line of the entry in the human output.
    var line: String {
      switch status {
      case .created: CLILocalized.format("cli.generate.group.created", file)
      case .replaced: CLILocalized.format("cli.generate.group.replaced", file)
      case .unchanged: CLILocalized.format("cli.generate.group.unchanged", file)
      case .notWritten: document ?? ""
      }
    }
  }

  /// Writes `documents` into `folder`, and writes none when a differing file stands in the way and
  /// `replace` is not set.
  ///
  /// - Throws: ``CLIFailure`` naming the file that differs or that cannot be written.
  static func write(_ documents: [GeneratedDocument], to folder: URL, replace: Bool) throws
    -> [Entry]
  {
    var entries: [Entry] = []
    for document in documents {
      let url = folder.appendingPathComponent(document.fileName)
      var status = Entry.Status.created
      if let existing = FileManager.default.contents(atPath: url.path) {
        status = existing == document.data ? .unchanged : .replaced
      }
      if status == .replaced && !replace {
        throw CLIFailure(
          .fileAccessFailed,
          CLILocalized.format("cli.generate.group.conflict", url.path)
        )
      }
      entries.append(Entry(document: document, status: status))
    }
    for (document, entry) in zip(documents, entries) where entry.status != .unchanged {
      let url = folder.appendingPathComponent(document.fileName)
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try document.data.write(to: url, options: .atomic)
      } catch {
        throw CLIFailure(
          .fileAccessFailed,
          CLILocalized.format("cli.generate.group.writeFailed", url.path, error.localizedDescription)
        )
      }
    }
    return entries
  }
}
