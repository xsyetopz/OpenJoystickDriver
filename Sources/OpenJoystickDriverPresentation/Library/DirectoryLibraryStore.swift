import Foundation
import OpenJoystickDriverKit

/// The store on disk: user records in `recordsDirectory`, packages beside it.
final class DirectoryLibraryStore: LibraryStore {
  /// The folder that holds the user's record files.
  let recordsDirectory: URL
  /// The folder that holds the installed mod packages, beside ``recordsDirectory``.
  let packagesDirectory: URL
  /// The version of the running app, which a package may require; nil leaves it unchecked.
  let runningVersion: String?
  /// The records loaded by the latest ``records()``; details and tests read this set.
  private let loaded = Locked<ControllerRecordSet?>(nil)

  /// Creates the store on a record folder; the packages folder lies beside it.
  init(
    recordsDirectory: URL = ControllerRecordSet.userDirectory,
    runningVersion: String? = nil
  ) {
    self.recordsDirectory = recordsDirectory
    packagesDirectory = ModPackageStore.directory(besides: recordsDirectory)
    self.runningVersion = runningVersion
  }

  /// The mod package store on ``packagesDirectory``.
  private var packages: ModPackageStore {
    ModPackageStore(directory: packagesDirectory, runningVersion: runningVersion)
  }

  /// Loads the records of the record directory and lists them by scope.
  ///
  /// The loaded set stays for the detail and test reads.
  ///
  /// - Returns: The installed records, the built-in records and the files that were skipped.
  func records() -> LibraryRecordListing {
    let set = ControllerRecordSet.load(userDirectory: recordsDirectory)
    loaded.withLock { $0 = set }
    return LibraryRecordListing(
      installed: set.records.values.filter { $0.layer != .bundled }.sorted { $0.model < $1.model }
        .map(Self.item),
      builtIn: ControllerRecordSet.bundled.records.values.sorted { $0.model < $1.model }.map {
        var item = Self.item($0)
        if let patch = set.records[$0.model], patch.layer != .bundled {
          item.patchedBy = patch.file?.lastPathComponent
        }
        return item
      },
      skipped: set.userFiles.compactMap { file in
        file.problem.map { LibrarySkippedFile(path: file.url.path, problem: $0) }
      }
    )
  }

  /// Returns the list item of `record`.
  private static func item(_ record: ControllerRecord) -> LibraryRecordItem {
    LibraryRecordItem(
      model: record.model,
      family: record.protocolID,
      layer: record.layer,
      file: record.file,
      appleSigned: record.isClaimedByUSBExtension == true
    )
  }

  /// Returns the full record of a model from the latest load.
  ///
  /// - Parameter model: The model of the record.
  /// - Returns: The detail, or nil when the latest load has no such record.
  func recordDetail(_ model: ControllerModelID) -> LibraryRecordDetail? {
    guard let record = loaded.withLock({ $0 })?.records[model] else { return nil }
    return LibraryRecordDetail(
      item: Self.item(record),
      transport: record.usesRawUSB ? "USB" : "HID",
      notes: record.notes,
      claimedByUSBExtension: record.isClaimedByUSBExtension,
      fields: record.fieldLayers.sorted { $0.key < $1.key }.map {
        LibraryRecordField(name: $0.key, layer: $0.value)
      },
      record: LibraryRecordDocument(document: record.text)
    )
  }

  /// Replays a capture through the record's parser and compares the state with the expectation.
  ///
  /// - Parameters:
  ///   - model: The record to test.
  ///   - capture: The packet capture, as JSON lines.
  ///   - captureName: The name that labels the capture in a failure.
  ///   - expectation: The expected state, as JSON.
  ///   - expectationName: The name that labels the expectation in a failure.
  /// - Returns: The result, which lists any differences.
  /// - Throws: ``LibraryFailure`` when the record is not loaded or a file cannot be read as its
  ///   kind.
  func testRecord(
    _ model: ControllerModelID,
    capture: Data,
    captureName: String,
    expectation: Data,
    expectationName: String
  ) throws -> ControllerRecordTestResult {
    guard let record = loaded.withLock({ $0 })?.records[model] else {
      throw LibraryFailure(
        message: OJDLocalized.formatted("cli.record.show.notFound", model.description),
        code: .notFound
      )
    }
    do { return try record.test(capture: capture, expectation: expectation) } catch let error
      as ControllerRecordTestError
    {
      throw LibraryFailure(
        message: error.message(
          model: model,
          capture: captureName,
          expectation: expectationName
        ),
        code: .invalidInputFile
      )
    }
  }

  /// Validates a record file and names the file it would be stored as.
  ///
  /// - Parameter data: The bytes of the record file.
  /// - Returns: The identity and file name of the record, and whether a file of that name exists.
  /// - Throws: ``LibraryFailure`` with the validation problem and its error code.
  func checkRecord(_ data: Data) throws -> LibraryRecordCheck {
    let validated: ValidatedControllerRecord
    do { validated = try ControllerRecordSet.validate(data) } catch {
      throw LibraryFailure(
        message: OJDLocalized.formatted(
          "ui.library.record.invalid",
          ControllerRecordSet.problemDescription(
            error,
            includingCode: false,
            document: "record",
            localization: Localization()
          )
        ),
        code: ControllerRecordSet.problemCode(error) ?? .invalidInputFile
      )
    }
    let destination = recordsDirectory.appendingPathComponent(validated.fileName)
    return LibraryRecordCheck(
      identity: Self.identity(of: validated),
      fileName: validated.fileName,
      replaces: FileManager.default.fileExists(atPath: destination.path)
    )
  }

  /// A validated file is a Controller file with a record or a patch with a selector.
  private static func identity(of validated: ValidatedControllerRecord) -> String {
    if let record = validated.record { return record.model.description }
    if let selector = validated.selector { return selector.description }
    preconditionFailure("A validated controller record file has a record or a selector")
  }

  /// Validates a record file and writes it to the record directory, which is created when missing.
  ///
  /// - Parameter data: The bytes of the record file.
  /// - Returns: The identity and file name of the installed record.
  /// - Throws: ``LibraryFailure`` when the file fails validation or cannot be written.
  func installRecord(_ data: Data) throws -> LibraryRecordCheck {
    let check = try checkRecord(data)
    let destination = recordsDirectory.appendingPathComponent(check.fileName)
    do {
      try FileManager.default.createDirectory(
        at: recordsDirectory,
        withIntermediateDirectories: true
      )
      try data.write(to: destination, options: .atomic)
    } catch {
      throw LibraryFailure(
        message: OJDLocalized.formatted(
          "ui.library.record.installFailed",
          destination.path,
          error.localizedDescription
        ),
        code: .fileAccessFailed
      )
    }
    return check
  }

  /// Removes the user's files for a model from the record directory.
  ///
  /// - Parameter model: The model of the record.
  /// - Throws: ``LibraryFailure`` when no file exists or one cannot be removed.
  func removeRecord(_ model: ControllerModelID) throws {
    let targets = [
      ControllerRecordSet.fileName(for: model), ControllerPatch.Selector.identity(model).fileName,
    ].map { recordsDirectory.appendingPathComponent($0) }
      .filter { FileManager.default.fileExists(atPath: $0.path) }
    guard !targets.isEmpty else {
      throw LibraryFailure(
        message: OJDLocalized.formatted("ui.library.record.notFound", model.description),
        code: .notFound
      )
    }
    for target in targets {
      do { try FileManager.default.removeItem(at: target) } catch {
        throw LibraryFailure(
          message: OJDLocalized.formatted(
            "ui.library.record.removeFailed",
            target.path,
            error.localizedDescription
          ),
          code: .fileAccessFailed
        )
      }
    }
  }

  /// Lists the installed mod packages.
  ///
  /// - Returns: One item for each package, with its manifest fields and the reason it is not used.
  func installedMods() -> [LibraryModItem] {
    packages.list().map { package in
      LibraryModItem(
        name: package.name,
        version: package.manifest?.version,
        author: package.manifest?.author,
        files: package.manifest.map(\.listedFiles) ?? [],
        problem: package.problem
      )
    }
  }

  /// Validates a mod package folder.
  ///
  /// - Parameter folder: The package folder.
  /// - Returns: The name, version, author and files of the package, and whether a package of that
  ///   name is installed.
  /// - Throws: ``LibraryFailure`` when the package is refused.
  func checkMod(folder: URL) throws -> LibraryModCheck {
    do {
      let manifest = try packages.validate(folder)
      let installed = packagesDirectory.appendingPathComponent(manifest.name, isDirectory: true)
      return LibraryModCheck(
        name: manifest.name,
        version: manifest.version,
        author: manifest.author,
        files: manifest.listedFiles,
        replaces: (try? FileManager.default.attributesOfItem(atPath: installed.path)) != nil
      )
    } catch let error as ModPackageError {
      throw Self.failure(error, subject: folder.path)
    }
  }

  /// Installs the mod package in a folder.
  ///
  /// - Parameters:
  ///   - folder: The package folder.
  ///   - replace: Whether an installed package of the same name may be replaced.
  /// - Throws: ``LibraryFailure`` when the package is refused.
  func installMod(folder: URL, replace: Bool) throws {
    do { _ = try packages.install(folder, replace: replace) } catch let error as ModPackageError {
      throw Self.failure(error, subject: folder.path)
    }
  }

  /// Removes the installed mod package called `name`.
  ///
  /// - Parameter name: The name of the package.
  /// - Throws: ``LibraryFailure`` when the package cannot be removed.
  func removeMod(name: String) throws {
    do { try packages.remove(name) } catch let error as ModPackageError {
      throw Self.failure(error, subject: name)
    }
  }

  /// Returns the failure for a refused mod package, naming `subject` and the reason.
  private static func failure(_ error: ModPackageError, subject: String) -> LibraryFailure {
    LibraryFailure(
      message: OJDLocalized.formatted("ui.library.mod.refused", subject, error.detail),
      code: error.code
    )
  }
}
