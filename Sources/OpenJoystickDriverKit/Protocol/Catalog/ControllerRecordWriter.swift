public import Foundation

/// Sets or removes one value in the user's controller-record directory: the `server` of a model,
/// or a `tuning` key of a model or of every controller.
///
/// An existing user file keeps every other key. A missing file becomes a ControllerPatch file
/// when the bundled catalog or an installed package has the model, because a patch applies over
/// one of their records; the `all` patch of ``ControllerDefaults`` needs no record. The record
/// watcher of the service applies the change.
public enum ControllerRecordWriter {
  /// What a tuning change applies to.
  public enum Target: Equatable, Sendable {
    /// One controller model: its user Controller file, or else its ControllerPatch file.
    case model(ControllerModelID)
    /// Every controller: `all.patch.plist`.
    case allControllers
  }

  /// A change of one `tuning` key.
  public enum TuningEdit: Equatable, Sendable {
    /// Sets `tuning.KEY` to a number.
    case set(ControllerTuning.Key, Double)
    /// Removes `tuning.KEY` from the user file, and `tuning` with its last key.
    case remove(ControllerTuning.Key)

    /// The key the edit sets or removes.
    public var key: ControllerTuning.Key {
      switch self {
      case .set(let key, _), .remove(let key): key
      }
    }
  }

  /// One planned change, before ``write(_:)`` stores it.
  public struct Change: Sendable {
    /// The effective server of the model before the change; `system` when no layer sets it and
    /// for ``Target/allControllers``.
    public let previousServer: ControllerServer
    /// The effective value of the edited tuning key before the change; nil when no layer sets it
    /// or the change sets `server`.
    public let previousTuning: Double?
    /// The user file the change writes or removes.
    public let file: URL
    /// Whether the change creates the file.
    public let created: Bool
    /// The bytes ``write(_:)`` stores, a valid user record; nil when the change removes the file
    /// because a patch has no key left.
    public let data: Data?
  }

  /// Why the change was refused.
  ///
  /// The file is unchanged.
  public enum Failure: Error, Equatable, Sendable {
    /// The user directory has no file for the model and neither the bundled catalog nor an
    /// installed package has a record of it, so there is nothing to patch. `ojd record draft`
    /// starts a Controller file.
    case noRecord(ControllerModelID)
    /// The existing user file is invalid, with its problem.
    case invalidFile(String)
    /// The changed record is invalid, such as `server` on a raw-USB family or a `stickDeadzone`
    /// out of range, with its problem.
    case invalidResult(String)
  }

  /// Why a tuning change was refused.
  ///
  /// The file is unchanged.
  public enum TuningFailure: Error, Equatable, Sendable {
    /// The record write was refused.
    case refused(Failure)
    /// The user file does not set the tuning key, so there is nothing to remove.
    case notSet(ControllerTuning.Key)
  }

  /// The change that sets `server` for `model` in `directory`. `records` is the loaded record
  /// set, which gives the effective server before the change.
  public static func change(
    _ server: ControllerServer,
    for model: ControllerModelID,
    records: ControllerRecordSet,
    directory: URL = ControllerRecordSet.userDirectory
  ) throws(Failure) -> Change {
    do {
      return try plan(
        for: .model(model),
        tuningKey: nil,
        records: records,
        directory: directory
      ) { (fields: inout [String: Any]) in fields["server"] = server.rawValue }
    } catch {
      switch error {
      case .record(let failure): throw failure
      case .edit(let never): switch never {}
      }
    }
  }

  /// The change that applies `edit` to `target` in `directory`. `records` is the loaded record
  /// set, which gives the effective value before the change.
  public static func change(
    _ edit: TuningEdit,
    for target: Target,
    records: ControllerRecordSet,
    directory: URL = ControllerRecordSet.userDirectory
  ) throws(TuningFailure) -> Change {
    do {
      return try plan(
        for: target,
        tuningKey: edit.key,
        records: records,
        directory: directory
      ) { (fields: inout [String: Any]) throws(NotSet) in try apply(edit, to: &fields) }
    } catch {
      switch error {
      case .record(let failure): throw .refused(failure)
      case .edit(let notSet): throw .notSet(notSet.key)
      }
    }
  }

  /// Stores `change` atomically, creating the user directory when it is missing, or removes the
  /// file when the change leaves a patch with no key.
  public static func write(_ change: Change) throws {
    guard let data = change.data else {
      try FileManager.default.removeItem(at: change.file)
      return
    }
    try FileManager.default.createDirectory(
      at: change.file.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: change.file, options: .atomic)
  }

  /// A tuning removal found no value to remove.
  private struct NotSet: Error {
    /// The tuning key that is not set.
    let key: ControllerTuning.Key
  }

  /// Why ``plan(for:tuningKey:records:directory:edit:)`` refused: the record, or the edit.
  private enum Refusal<EditFailure: Error>: Error {
    /// The record could not be changed.
    case record(Failure)
    /// The edit could not be applied.
    case edit(EditFailure)
  }

  /// The change that `edit` makes to the members of the Controller file, or to the `patch` of the
  /// ControllerPatch file, of `target`. `tuningKey` is the key the edit changes, if any.
  private static func plan<EditFailure: Error>(
    for target: Target,
    tuningKey: ControllerTuning.Key?,
    records: ControllerRecordSet,
    directory: URL,
    edit: (inout [String: Any]) throws(EditFailure) -> Void
  ) throws(Refusal<EditFailure>) -> Change {
    let selector: ControllerPatch.Selector
    var controllerFile: URL?
    switch target {
    case .model(let model):
      selector = .identity(model)
      controllerFile = directory.appendingPathComponent(ControllerRecordSet.fileName(for: model))
    case .allControllers:
      selector = .all
    }
    let patchFile = directory.appendingPathComponent(selector.fileName)
    let packages = ControllerRecordSet.packageRecords(
      in: ModPackageStore.directory(besides: directory)
    ).records
    let existingController = controllerFile.flatMap { try? Data(contentsOf: $0) }
    let existing = existingController ?? (try? Data(contentsOf: patchFile))
    let file = existingController == nil ? patchFile : controllerFile ?? patchFile
    let document: [String: Any]?
    if let existing {
      document = try updated(existing, file: file, packages: packages, edit: edit)
    } else {
      if case .model(let model) = target, packages[model] == nil { throw .record(.noRecord(model)) }
      var body: [String: Any] = [:]
      do { try edit(&body) } catch { throw .edit(error) }
      document = ControllerPatch.document(selector: selector, body: body)
    }
    let data: Data?
    do {
      data = try document.map { document in
        let encoded = try DocumentCoder.write(document)
        _ = try ControllerRecordSet.validate(encoded, file: file, packages: packages)
        return encoded
      }
    } catch {
      throw .record(
        .invalidResult(ControllerRecordSet.problemDescription(error, document: "record"))
      )
    }
    let effective: ControllerRecord?
    let tuning: [ControllerTuningValue]
    switch target {
    case .model(let model):
      effective = records.records[model] ?? packages[model]
      tuning = effective?.tuningValues ?? []
    case .allControllers:
      effective = nil
      tuning = records.defaultTuningValues
    }
    return Change(
      previousServer: effective?.profile.server ?? .system,
      previousTuning: tuningKey.flatMap { key in tuning.first { $0.key == key }?.value },
      file: file,
      created: existing == nil,
      data: data
    )
  }

  /// The existing user file with `edit` applied in the Controller file or in the `patch` of the
  /// ControllerPatch file; nil when a removal leaves a patch with no key and no `remove`.
  private static func updated<EditFailure: Error>(
    _ data: Data,
    file: URL,
    packages: [ControllerModelID: ControllerRecord],
    edit: (inout [String: Any]) throws(EditFailure) -> Void
  ) throws(Refusal<EditFailure>) -> [String: Any]? {
    let operation: ControllerRecordOperation
    do {
      operation = try ControllerRecordSet.validate(data, file: file, packages: packages).operation
    } catch {
      throw .record(
        .invalidFile(ControllerRecordSet.problemDescription(error, document: "record"))
      )
    }
    guard
      var document = (try? DocumentCoder.read(data, file: file.lastPathComponent))
        as? [String: Any]
    else {
      throw .record(.invalidFile("the file is not a dictionary"))
    }
    if operation == .add {
      do { try edit(&document) } catch { throw .edit(error) }
      return document
    }
    var fields = document["patch"] as? [String: Any] ?? [:]
    do { try edit(&fields) } catch { throw .edit(error) }
    if fields.isEmpty {
      guard document["remove"] != nil else { return nil }
      document["patch"] = nil
    } else {
      document["patch"] = fields
    }
    return document
  }
}

extension ControllerRecordWriter {
  /// `fields`, the members of a Controller file or the `patch` of a ControllerPatch file, with
  /// `edit` applied.
  ///
  /// A whole number is written without a fraction, so an integer key reads it.
  private static func apply(_ edit: TuningEdit, to fields: inout [String: Any]) throws(NotSet) {
    var tuning = fields["tuning"] as? [String: Any] ?? [:]
    switch edit {
    case .set(let key, let value):
      tuning[key.rawValue] = Int(exactly: value).map { $0 as Any } ?? value
    case .remove(let key):
      guard tuning.removeValue(forKey: key.rawValue) != nil else { throw NotSet(key: key) }
    }
    fields["tuning"] = tuning.isEmpty ? nil : tuning
  }
}
