public import Foundation

/// One file of a layer, and the package that holds it, or nil for the user's file.
struct ControllerLayerEntry {
  /// The location of the file.
  let url: URL
  /// The name of the package that holds the file; nil for the user's file.
  let owner: String?
}

extension ControllerRecordSet {
  /// The bundled catalog with the records and patches of the installed packages applied, then those
  /// of the valid `.plist` files in `directory`.
  ///
  /// The descriptions of the documented families are loaded first, from the user's `Protocols`
  /// folder and the installed packages; a description that is refused is listed in ``userFiles``.
  ///
  /// A missing directory holds no records; one that cannot be read is listed in ``userFiles`` with
  /// its reason. `all.patch.plist` in `directory` is the user's global ``ControllerDefaults``; it
  /// is the first patch of the user layer and is reported in ``defaults`` rather than in
  /// ``userFiles``. A `unit` patch in `directory` gives the calibration of its unit in
  /// ``unitCalibrations``.
  public static func load(
    userDirectory directory: URL = userDirectory,
    localization: Localization = Localization()
  ) -> Self {
    let protocolFiles = DocumentedProtocolFamilies.load(besides: directory).refused
    var packaged = packageRecords(
      in: ModPackageStore.directory(besides: directory),
      localization: localization
    )
    var defaults = ControllerDefaults.load(from: ControllerDefaults.file(in: directory))
    let urls: [URL]
    let stale: [ControllerRecordFile]
    do {
      let listed = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      ).sorted { $0.lastPathComponent < $1.lastPathComponent }
      urls = listed.filter { $0.pathExtension == "plist" }
      stale = listed.filter { $0.pathExtension == "json" }.map {
        ControllerRecordFile(
          url: $0,
          model: nil,
          operation: nil,
          problem: DocumentMigrator.staleProblem
        )
      }
    } catch CocoaError.fileReadNoSuchFile {
      urls = []
      stale = []
    } catch {
      let file = ControllerRecordFile(
        url: directory,
        model: nil,
        operation: nil,
        problem: "cannot read the directory: \(error.localizedDescription)"
      )
      return Self(
        records: packaged.records,
        userFiles: protocolFiles + [file] + packaged.files,
        defaults: defaults
      )
    }
    var records = packaged.records
    let applied = applyLayer(
      urls.map { ControllerLayerEntry(url: $0, owner: nil) },
      layer: .user,
      localization: localization,
      to: &records
    )
    for (model, url) in applied.replaced { packaged.overridden(model, by: url) }
    if let all = applied.files.first(where: { $0.url == defaults.url }), defaults.problem == nil,
      let problem = all.problem
    {
      defaults = ControllerDefaults(
        url: defaults.url,
        tuning: defaults.tuning,
        problem: problem,
        patch: nil
      )
    }
    return Self(
      records: records,
      userFiles: protocolFiles + applied.files.filter { $0.url != defaults.url } + stale
        + packaged.files,
      defaults: defaults,
      unitCalibrations: applied.units
    )
  }

  /// Applies the files of one layer to `records`: the Controller files first, which add or replace
  /// a record, then the patches in the order of ``ControllerPatchMerge/ordered(_:)``, with a
  /// package name breaking a tie.
  ///
  /// A file that fails is skipped and reported in the returned files, which follow the order of
  /// `entries`. `replaced` lists the models a user Controller file replaced, and `units` the
  /// calibration each `unit` patch of the user layer sets; a package holds no `unit` patch.
  static func applyLayer(
    _ entries: [ControllerLayerEntry],
    layer: ControllerRecordLayer,
    localization: Localization = Localization(),
    to records: inout [ControllerModelID: ControllerRecord]
  ) -> (
    files: [ControllerRecordFile], replaced: [(ControllerModelID, URL)],
    units: [ControllerPortKey: ControllerCalibration]
  ) {
    var state = LayerApplication()
    for entry in entries {
      do {
        try readLayerEntry(entry, layer: layer, records: &records, state: &state)
      } catch {
        state.results[entry.url] = ControllerRecordFile(
          url: entry.url,
          model: nil,
          operation: nil,
          problem: problemDescription(
            error,
            document: "record",
            localization: localization,
            file: entry.url.lastPathComponent
          )
        )
      }
    }
    for (entry, patch) in ControllerPatchMerge.ordered(
      state.patches,
      by: { ($0.patch, $0.entry.owner) }
    ) {
      state.results[entry.url] = applyLayerPatch(
        patch,
        entry: entry,
        layer: layer,
        localization: localization,
        to: &records
      )
    }
    return (entries.compactMap { state.results[$0.url] }, state.replaced, state.units)
  }

  /// What reading the files of one layer collects.
  private struct LayerApplication {
    var results: [URL: ControllerRecordFile] = [:]
    var units: [ControllerPortKey: ControllerCalibration] = [:]
    var patches: [(entry: ControllerLayerEntry, patch: ControllerPatch)] = []
    var owners: [ControllerModelID: String] = [:]
    var replaced: [(ControllerModelID, URL)] = []
  }

  /// Reads one file of a layer: a Controller file replaces a record, a `unit` patch sets a
  /// calibration, and any other patch is collected for the merge order of its layer.
  private static func readLayerEntry(
    _ entry: ControllerLayerEntry,
    layer: ControllerRecordLayer,
    records: inout [ControllerModelID: ControllerRecord],
    state: inout LayerApplication
  ) throws {
    let name = entry.url.lastPathComponent
    switch try parse(Data(contentsOf: entry.url), file: entry.url, layer: layer) {
    case .record(let record):
      guard name == fileName(for: record.model) else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.userFile.fileNameRecord",
          arguments: [fileName(for: record.model)],
          "the file name must be \(fileName(for: record.model))"
        )
      }
      if let owner = entry.owner {
        if let other = state.owners[record.model] {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            key: "error.E5007.userFile.packageSameController",
            arguments: [other],
            "same controller as package \(other)"
          )
        }
        state.owners[record.model] = owner
      }
      records[record.model] = record
      if layer == .user { state.replaced.append((record.model, entry.url)) }
      state.results[entry.url] = ControllerRecordFile(
        url: entry.url,
        model: record.model,
        operation: .add,
        problem: nil
      )
    case .patch(let patch):
      guard name == patch.selector.fileName else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.userFile.fileNamePatch",
          arguments: [patch.selector.fileName],
          "the file name must be \(patch.selector.fileName)"
        )
      }
      if case .unit(let model, let unit) = patch.selector {
        state.units[unit] = try unitCalibration(patch, over: records[model], layer: layer)
        state.results[entry.url] = ControllerRecordFile(
          url: entry.url,
          model: model,
          operation: .patch,
          problem: nil
        )
      } else {
        state.patches.append((entry, patch))
      }
    }
  }

  /// Applies `patch` to every record its selector selects and returns the file's result, which
  /// holds the first failure.
  private static func applyLayerPatch(
    _ patch: ControllerPatch,
    entry: ControllerLayerEntry,
    layer: ControllerRecordLayer,
    localization: Localization,
    to records: inout [ControllerModelID: ControllerRecord]
  ) -> ControllerRecordFile {
    let targets = records.keys.filter { patch.selector.selects($0) }.sorted()
    var failure: String?
    if targets.isEmpty, patch.selector != .all {
      failure = ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.userFile.unknownController",
        arguments: [patch.selector.description],
        "\(patch.selector.description) is not a known controller; use a Controller file"
      ).localizedDescription(localization, file: entry.url.lastPathComponent)
    }
    for target in targets {
      guard let record = records[target] else {
        preconditionFailure("every target comes from the keys of records")
      }
      do {
        records[target] = try apply(patch, to: record, layer: layer, file: entry.url)
      } catch {
        failure =
          failure
          ?? problemDescription(
            error,
            document: "record",
            localization: localization,
            file: entry.url.lastPathComponent
          )
      }
    }
    let model: ControllerModelID? =
      switch patch.selector {
      case .all: nil
      case .identity(let model): model
      case .model: targets.first
      case .unit(let model, _): model
      }
    return ControllerRecordFile(
      url: entry.url,
      model: model,
      operation: .patch,
      problem: failure
    )
  }

  /// The calibration that the `unit` patch `patch` sets over `record`, the record of its model.
  ///
  /// The values are range-checked as the record's own `tuning`. A patch outside the user layer, or
  /// for a model with no record, is refused.
  static func unitCalibration(
    _ patch: ControllerPatch,
    over record: ControllerRecord?,
    layer: ControllerRecordLayer
  ) throws -> ControllerCalibration {
    guard layer == .user else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.userFile.unitPatchNotUser",
        "a unit patch applies only from your Controllers folder"
      )
    }
    guard let record else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.userFile.unknownController",
        arguments: [patch.selector.description],
        "\(patch.selector.description) is not a known controller; use a Controller file"
      )
    }
    var base = try ordered(record.document, file: "record")
    for key in ControllerCalibration.keys {
      base = ControllerPatchMerge.removing(["tuning", key.rawValue], from: base)
    }
    let merged = ControllerPatchMerge.mergeRecordPatch(base, patch.body)
    let values = try decode(merged).document.tuning.calibration.values
    return ControllerCalibration(
      values: values.filter { key, _ in patch.body["tuning"]?[key.rawValue] != nil }
    )
  }

  /// A file of a layer, read.
  enum ParsedFile {
    /// A ``ControllerRecord`` file.
    case record(ControllerRecord)
    /// A ``ControllerPatch`` file.
    case patch(ControllerPatch)
  }

  /// Reads one Controller or ControllerPatch file.
  ///
  /// A document of any other kind is refused by the ControllerPatch header check. Both kinds
  /// refuse, by ``ordered(_:file:)``, a file that is not an XML property list.
  static func parse(_ data: Data, file: URL?, layer: ControllerRecordLayer) throws -> ParsedFile {
    let document = try ordered(data, file: file?.lastPathComponent ?? "record")
    guard document.members != nil else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.userFile.notDictionary",
        "the file is not a dictionary"
      )
    }
    if document["kind"]?.string == ControllerRecordDocument.kind {
      try OpenJoystickDriverAPI.requireHeader(
        apiVersion: document["apiVersion"],
        kind: document["kind"],
        expected: ControllerRecordDocument.kind,
        file: file?.lastPathComponent
      )
      let decoded = try decode(document)
      try refuseBootloader(bundled.records[decoded.model])
      guard bundled.records[decoded.model] == nil else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.userFile.bundledController",
          arguments: ["\(decoded.model)"],
          "\(decoded.model) is a bundled controller; use a patch to change it"
        )
      }
      let layers = Dictionary(
        uniqueKeysWithValues: fieldNames(of: document).map { ($0, layer) }
      )
      return .record(
        try makeRecord(
          document,
          layers: layers,
          userFile: layer == .user ? file : nil,
          packageFile: layer == .package ? file : nil
        )
      )
    }
    return .patch(try ControllerPatch.parse(document, file: file?.lastPathComponent))
  }

  /// Validates one record file against the bundled catalog: a Controller file's shape and
  /// cross-field checks, or a ControllerPatch file's shape and the record it gives when applied
  /// over the bundled record of its selector.
  ///
  /// `file` becomes the record's ``ControllerRecord/userFile``, or its
  /// ``ControllerRecord/packageFile`` when `layer` is `Package`. A patch of a model with no bundled
  /// record applies over its record in `packages`, the installed package records. An `all` patch
  /// gives no record; its `tuning` is range-checked.
  public static func validate(
    _ data: Data,
    file: URL? = nil,
    layer: ControllerRecordLayer = .user,
    packages: [ControllerModelID: ControllerRecord] = [:]
  ) throws -> ValidatedControllerRecord {
    switch try parse(data, file: file, layer: layer) {
    case .record(let record):
      return ValidatedControllerRecord(operation: .add, record: record, selector: nil)
    case .patch(let patch):
      if case .unit(let model, _) = patch.selector {
        let upstream = bundled.records[model] ?? packages[model]
        _ = try unitCalibration(patch, over: upstream, layer: layer)
        return ValidatedControllerRecord(operation: .patch, record: nil, selector: patch.selector)
      }
      if patch.selector == .all {
        _ = try ControllerDefaults.validate(data, file: file?.lastPathComponent)
        return ValidatedControllerRecord(operation: .patch, record: nil, selector: .all)
      }
      let upstream =
        bundled.records.values.sorted { $0.model < $1.model }
        .first { patch.selector.selects($0.model) }
        ?? packages.values.sorted { $0.model < $1.model }.first { patch.selector.selects($0.model) }
      guard let upstream else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.userFile.unknownController",
          arguments: [patch.selector.description],
          "\(patch.selector.description) is not a known controller; use a Controller file"
        )
      }
      return ValidatedControllerRecord(
        operation: .patch,
        record: try apply(patch, to: upstream, layer: layer, file: file),
        selector: patch.selector
      )
    }
  }

  /// Throws when `record` is a bootloader identity: its idle default mode is the bundled catalog's
  /// to keep, so no user or package file adds, replaces or patches it.
  private static func refuseBootloader(_ record: ControllerRecord?) throws {
    guard let record, record.profile.idleReason == .bootloader else { return }
    throw ControllerRecordProblem(
      code: .invalidControllerRecord,
      key: "error.E5007.userFile.bootloaderController",
      arguments: ["\(record.model)"],
      "\(record.model) is a bootloader identity; no user or package file changes it"
    )
  }

  /// `upstream` with `patch` merged in by ``ControllerPatchMerge/apply(_:to:)`` and validated as a
  /// record.
  ///
  /// An `all` patch sets only the tuning keys the family reads, and attributes them to
  /// ``ControllerRecordLayer/global``.
  static func apply(
    _ patch: ControllerPatch,
    to upstream: ControllerRecord,
    layer: ControllerRecordLayer,
    file: URL?
  ) throws -> ControllerRecord {
    let base = try ordered(upstream.document, file: "record")
    guard base.members != nil else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.userFile.upstreamNotDictionary",
        "the record is not a dictionary"
      )
    }
    let isAll = patch.selector == .all
    if !isAll { try refuseBootloader(upstream) }
    let body = ControllerPatchMerge.appliedBody(of: patch, to: base)
    let removed = ControllerPatchMerge.appliedRemove(of: patch, to: base)
    guard body != nil || !removed.isEmpty else { return upstream }
    let merged = ControllerPatchMerge.apply(patch, to: base)
    if !isAll, merged.hasSameValue(as: base) {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.userFile.patchNoChange",
        "the patch changes nothing in the record"
      )
    }
    let (layers, tuningLayers) = attributedLayers(
      of: upstream,
      removed: removed,
      body: body,
      layer: layer,
      isAll: isAll
    )
    return try makeRecord(
      merged,
      layers: layers,
      tuningLayers: tuningLayers,
      userFile: layer == .user && !isAll ? file : upstream.userFile,
      packageFile: layer == .package && !isAll ? file : upstream.packageFile
    )
  }

  /// The field and tuning layers of `upstream` after a patch removes `removed` paths and sets the
  /// members of `body`.
  ///
  /// A patch outside `all` attributes the fields it touches to `layer`. An `all` patch attributes
  /// its tuning settings to ``ControllerRecordLayer/global``.
  private static func attributedLayers(
    of upstream: ControllerRecord,
    removed: [[String]],
    body: OrderedJSON?,
    layer: ControllerRecordLayer,
    isAll: Bool
  ) -> (fields: [String: ControllerRecordLayer], tuning: [String: ControllerRecordLayer]) {
    var layers = upstream.fieldLayers
    var tuningLayers = upstream.tuningLayers
    for path in removed {
      let section = path[0]
      if path.count == 1 {
        layers[section] = nil
        if section == "tuning" { tuningLayers = [:] }
      } else if section == "tuning" {
        tuningLayers[path[1]] = nil
        if !isAll { layers[section] = layer }
      } else {
        layers[section] = layer
      }
    }
    for member in body?.members ?? [] {
      let (key, value) = (member.key, member.value)
      if !isAll { layers[key] = layer }
      if key == "tuning" {
        for setting in value.members ?? [] { tuningLayers[setting.key] = isAll ? .global : layer }
      }
    }
    return (layers, tuningLayers)
  }
}
