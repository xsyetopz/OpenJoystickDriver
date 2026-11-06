import Foundation

extension RepositoryValidation {
  /// Applies the built-in patches under `patches` to the Controller files under `controllers` with
  /// ``ControllerPatchMerge`` and writes each effective record to the same relative path under
  /// `output`.
  ///
  /// Nothing is written when any problem is found.
  ///
  /// A record's members are written in the order of its file, then the members that patches add
  /// in the order of the patch that adds them, at every depth. An array or value that a patch
  /// replaces takes the order of the patch, and every number keeps the text of the file that
  /// wrote it.
  ///
  /// A patch file must hold a valid ``ControllerPatch`` at the path its selector gives: the
  /// vendor directory for a `vendorID` with `productID`, the top of `patches` for the others. A
  /// patch file at any other path, such as one in a deeper directory, is refused. Record files
  /// are read at any depth and written at the same relative path. A patch that selects no
  /// record, and one that changes nothing in a record other than the `all` patch, are problems.
  package static func applyPatches(
    controllers: URL,
    patches: URL,
    output: URL
  ) -> [RepositoryProblem] {
    var problems: [RepositoryProblem] = []
    let patchFiles = readPatches(under: patches, problems: &problems)
    let recordFiles = readRecords(under: controllers, problems: &problems)
    var selected: Set<URL> = []
    var effective: [(file: RecordFile, document: OrderedJSON)] = []
    for file in recordFiles {
      var document = file.document
      let chosen = ControllerPatchMerge.ordered(
        patchFiles.filter { $0.patch.selector.selects(file.model) }
      ) { ($0.patch, nil) }
      for entry in chosen {
        selected.insert(entry.url)
        let merged = ControllerPatchMerge.apply(entry.patch, to: document)
        if entry.patch.selector != .all, merged.hasSameValue(as: document) {
          problems.append(
            RepositoryProblem(
              file: entry.url.path,
              code: .invalidControllerRecord,
              message: "the patch changes nothing in \(file.model)"
            )
          )
        }
        document = merged
      }
      effective.append((file, document))
    }
    for entry in patchFiles where entry.patch.selector != .all && !selected.contains(entry.url) {
      problems.append(
        RepositoryProblem(
          file: entry.url.path,
          code: .invalidControllerRecord,
          message: "\(entry.patch.selector.description) is not a known controller"
        )
      )
    }
    guard problems.isEmpty else { return problems }
    do {
      for (file, document) in effective {
        let destination = output.appendingPathComponent(file.relativePath)
        try FileManager.default.createDirectory(
          at: destination.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try document.formattedData().write(to: destination, options: .atomic)
      }
    } catch {
      return [
        RepositoryProblem.fileAccess(output.path, error)
      ]
    }
    return []
  }

  /// A patch file read from the patch directory.
  private struct PatchFile {
    /// The location of the file.
    let url: URL
    /// The parsed patch.
    let patch: ControllerPatch
  }

  /// A record file read from the record directory.
  private struct RecordFile {
    /// The path of the file below the record directory.
    let relativePath: String
    /// The controller model that the record describes.
    let model: ControllerModelID
    /// The record as written, with its member order.
    let document: OrderedJSON
  }

  /// Reads each JSON file under `directory` as a record and appends a problem to `problems` for
  /// each file that is not a valid record.
  /// - Returns: The records that read.
  private static func readRecords(
    under directory: URL,
    problems: inout [RepositoryProblem]
  ) -> [RecordFile] {
    let urls: [URL]
    switch jsonFiles(under: directory) {
    case .failure(let problem):
      problems.append(problem)
      return []
    case .success(let found): urls = found
    }
    var files: [RecordFile] = []
    for url in urls {
      do {
        let data = try RepositoryProblem.read(url)
        try ControllerRecordSet.requireUTF8(data)
        let document = try ControllerRecordSet.ordered(data)
        guard let vendorID = document["vendorID"]?.integer.flatMap(UInt16.init(exactly:)),
          let productID = document["productID"]?.integer.flatMap(UInt16.init(exactly:))
        else {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            "vendorID must be 1...65535 and productID 0...65535"
          )
        }
        files.append(
          RecordFile(
            relativePath: relativePath(of: url, under: directory),
            model: ControllerModelID(vendorID: vendorID, productID: productID),
            document: document
          )
        )
      } catch {
        problems.append(RepositoryProblem(file: url.path, error: error, document: "record"))
      }
    }
    return files
  }

  /// Reads each JSON file under `directory` as a patch and appends a problem to `problems` for each
  /// file that is not a valid patch or that is not stored at the path of its selector.
  /// - Returns: The patches that read.
  private static func readPatches(
    under directory: URL,
    problems: inout [RepositoryProblem]
  ) -> [PatchFile] {
    let urls: [URL]
    switch jsonFiles(under: directory) {
    case .failure(let problem):
      problems.append(problem)
      return []
    case .success(let found): urls = found
    }
    var patches: [PatchFile] = []
    for url in urls {
      do {
        let data = try RepositoryProblem.read(url)
        try ControllerRecordSet.requireUTF8(data)
        let order = try ControllerRecordSet.ordered(data)
        let patch = try ControllerPatch.parse(order, file: url.lastPathComponent)
        let expected = patchPath(of: patch.selector)
        guard relativePath(of: url, under: directory) == expected else {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            "the patch path must be \(expected)"
          )
        }
        patches.append(PatchFile(url: url, patch: patch))
      } catch {
        problems.append(RepositoryProblem(file: url.path, error: error, document: "patch"))
      }
    }
    return patches
  }

  /// Where a built-in patch with `selector` is stored under the patch directory.
  private static func patchPath(of selector: ControllerPatch.Selector) -> String {
    guard case .identity(let model) = selector else { return selector.fileName }
    return String(format: "%04x/", model.vendorID) + selector.fileName
  }

  /// The path of `url` below `directory`, with `/` between components.
  private static func relativePath(of url: URL, under directory: URL) -> String {
    let root = directory.standardizedFileURL.pathComponents
    return url.standardizedFileURL.pathComponents.dropFirst(root.count).joined(separator: "/")
  }
}
