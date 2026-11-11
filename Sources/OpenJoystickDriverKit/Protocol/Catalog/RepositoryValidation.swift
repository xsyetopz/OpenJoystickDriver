import Foundation

/// One file that fails a check of a repository tool, and why.
package struct RepositoryProblem: Error, Equatable, Sendable {
  /// The path of the file, or the name of a file that is absent.
  package let file: String
  /// The catalog code of the failed rule, or ``ErrorCode/fileAccessFailed`` for a file that
  /// cannot be read or written.
  package let code: ErrorCode
  /// The reason, without the code.
  package let message: String

  /// Creates a problem for a file, the code of the failed rule and the reason.
  package init(file: String, code: ErrorCode, message: String) {
    self.file = file
    self.code = code
    self.message = message
  }

  /// The problem that `error` reports for `file`, with the code that
  /// ``ControllerRecordSet/problemCode(_:)`` gives and the reason that
  /// ``ControllerRecordSet/problemDescription(_:includingCode:document:)`` gives for a `document`
  /// of that kind.
  ///
  /// A ``RepositoryProblem`` is reported as it is. The record, patch and virtual device checks
  /// throw only errors that ``ControllerRecordSet/problemCode(_:)`` names, so any other error stops
  /// the tool.
  init(file: String, error: any Error, document: String) {
    if let problem = error as? Self {
      self = problem
      return
    }
    guard let code = ControllerRecordSet.problemCode(error) else {
      preconditionFailure("a record check threw an error with no code: \(type(of: error))")
    }
    self.init(
      file: file,
      code: code,
      message: ControllerRecordSet.problemDescription(
        error,
        includingCode: false,
        document: document
      )
    )
  }

  /// The problem of the file `file` that cannot be read or written, for `error`.
  static func fileAccess(_ file: String, _ error: any Error) -> Self {
    Self(file: file, code: .fileAccessFailed, message: error.localizedDescription)
  }

  /// The bytes of the file `url`, or the ``ErrorCode/fileAccessFailed`` problem of reading it.
  static func read(_ url: URL) throws(Self) -> Data {
    do { return try Data(contentsOf: url) } catch { throw fileAccess(url.path, error) }
  }
}

/// The checks that the repository tool runs over files outside the bundle.
///
/// Each check is the one the bundled files and the user's files pass, applied to the files it is
/// given.
package enum RepositoryValidation {
  /// The problems of the Controller files under `directory`, found recursively, by
  /// ``ControllerRecordSet``: each file's record rules, the file name its record needs, and an
  /// identity that is not held twice.
  package static func controllers(in directory: URL) -> [RepositoryProblem] {
    switch plistFiles(under: directory) {
    case .failure(let problem): return [problem]
    case .success(let urls):
      guard !urls.isEmpty else {
        return [
          RepositoryProblem(
            file: directory.path,
            code: .invalidControllerRecord,
            message: "controller catalog is empty"
          )
        ]
      }
      return ControllerRecordSet.loadCatalog(urls).problems
    }
  }

  /// The problems of the protocol descriptions under `directory`: each file's own rules, the
  /// family its file name must name, and a family without a file.
  package static func descriptions(in directory: URL) -> [RepositoryProblem] {
    switch plistFiles(under: directory) {
    case .failure(let problem): return [problem]
    case .success(let urls):
      return ProtocolDescription.loadCatalog(urls, missing: directory.path).problems
    }
  }

  /// The problem of the remapping profile file `url`, or nil when ``RemappingProfileFileStore``
  /// loads it.
  ///
  /// A file that cannot be read is ``ErrorCode/fileAccessFailed``.
  package static func profile(at url: URL) -> RepositoryProblem? {
    do {
      _ = try RemappingProfileFileStore.load(from: try RepositoryProblem.read(url))
    } catch let problem as RepositoryProblem {
      return problem
    } catch {
      return RepositoryProblem(
        file: url.path,
        code: RemappingProfileFileStore.problemCode(error),
        message: ControllerRecordSet.problemDescription(
          error,
          includingCode: false,
          document: "profile"
        )
      )
    }
    return nil
  }

  /// The problem of the `VirtualDevice` file `url`, or nil when ``VirtualHIDProfileOverrideStore``
  /// reads it.
  ///
  /// A file that cannot be read is ``ErrorCode/fileAccessFailed``.
  package static func virtualDevice(at url: URL) -> RepositoryProblem? {
    do { _ = try VirtualHIDProfileOverrideStore.parse(try RepositoryProblem.read(url)) } catch {
      return RepositoryProblem(file: url.path, error: error, document: "virtualDevice")
    }
    return nil
  }

  /// The `.plist` files under `directory`, found recursively, in path order.
  static func plistFiles(under directory: URL) -> Result<[URL], RepositoryProblem> {
    guard
      let walker = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
    else {
      return .failure(
        RepositoryProblem(
          file: directory.path,
          code: .fileAccessFailed,
          message: "cannot read the directory"
        )
      )
    }
    let urls = walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "plist" }
    return .success(urls.sorted { $0.path < $1.path })
  }
}
