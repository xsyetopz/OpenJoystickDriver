import Foundation

/// The bundled records with the records of the installed packages applied, and the package files.
struct ControllerPackageRecords {
  /// The records by model, as the installed packages leave them.
  var records: [ControllerModelID: ControllerRecord]
  /// The package files that were read, each with the reason it was skipped, if any.
  var files: [ControllerRecordFile] = []

  /// Lists the package file of `model` as skipped, because the user's file `url` replaces it.
  mutating func overridden(_ model: ControllerModelID, by url: URL) {
    files = files.map { file in
      guard file.model == model, file.problem == nil else { return file }
      return ControllerRecordFile(
        url: file.url,
        model: model,
        operation: file.operation,
        problem: "replaced by your file \(url.lastPathComponent)"
      )
    }
  }
}

extension ControllerRecordSet {
  /// The records of the packages in `directory`, in package-name order.
  ///
  /// A package that cannot be used, such as one whose `requires` leaves out the running version, is
  /// skipped and its `mod.json` is listed with the reason. A package record that fails validation,
  /// has the wrong file name, or repeats the model of an earlier package's record is skipped and
  /// listed with its reason. `runningVersion` is the OJD version that the `requires` of a package
  /// is checked against; nil means the running one. Package Controller files apply first, then the
  /// package patches in the order of ``ControllerPatchMerge/ordered(_:)``.
  static func packageRecords(
    in directory: URL,
    runningVersion: String? = nil
  ) -> ControllerPackageRecords {
    var packaged = ControllerPackageRecords(records: bundled.records)
    var entries: [ControllerLayerEntry] = []
    var manifestProblems: [(position: Int, file: ControllerRecordFile)] = []
    for package in ModPackageStore(directory: directory, runningVersion: runningVersion).list() {
      guard let manifest = package.manifest, package.problem == nil else {
        manifestProblems.append(
          (
            entries.count,
            ControllerRecordFile(
              url: package.directory.appendingPathComponent(ModPackageManifest.fileName),
              model: nil,
              operation: nil,
              problem: package.problem
            )
          )
        )
        continue
      }
      entries += (manifest.controllers + manifest.patches).sorted().map {
        ControllerLayerEntry(
          url: package.directory.appendingPathComponent("Controllers/\($0)"),
          owner: package.name
        )
      }
    }
    let applied = applyLayer(entries, layer: .package, to: &packaged.records).files
    for position in 0...applied.count {
      packaged.files += manifestProblems.filter { $0.position == position }.map(\.file)
      if position < applied.count { packaged.files.append(applied[position]) }
    }
    return packaged
  }
}
