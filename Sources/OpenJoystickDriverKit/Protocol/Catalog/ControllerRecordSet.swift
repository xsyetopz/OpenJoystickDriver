import Foundation

/// Where one part of an effective controller record comes from. The cases are in precedence
/// order, lowest first: a later layer wins over an earlier one.
public enum ControllerRecordLayer: String, Codable, CaseIterable, Sendable {
  /// OJD's built-in default, used when no other layer sets a value.
  case driver
  /// The user's `Defaults.json`.
  case global
  /// The signed catalog in the app bundle.
  case bundled
  /// A file in the user's controller-record directory.
  case user
  /// The active remapping profile.
  case profile
}

/// The operation of a user controller record, from `controller-override.schema.json`.
public enum ControllerRecordOperation: String, Codable, Sendable {
  /// A record for an identity the bundled catalog does not have.
  case add
  /// Fields that replace the same fields of a bundled record.
  case patch
}

/// One effective controller record: a bundled record, a user `add`, or a bundled record with a
/// user `patch` applied.
public struct ControllerRecord: Sendable {
  public let identity: ControllerIdentity
  /// The merged record as a `controller.schema.json` document, with sorted keys.
  public let document: Data
  /// The layer of each top-level field of `document`, except `$schema`, `vendorID`, and
  /// `productID`.
  public let fieldLayers: [String: ControllerRecordLayer]
  /// The layer of each effective `tuning` key, by its JSON name: `bundled`, `user`, or `global`.
  /// A key no layer sets is absent, and the driver default applies.
  public let tuningLayers: [String: ControllerRecordLayer]
  /// The user file that adds or patches this record, or nil for a bundled record.
  public let userFile: URL?
  /// The protocol family, such as `xbox.gip`.
  public let family: String
  /// The tuning keys this record's family reads.
  let tuningScope: Set<ControllerTuning.Key>
  let profile: DeviceRuntimeProfile

  /// The effective tuning: the global defaults under the record's own values, per key.
  public var tuning: ControllerTuning { profile.tuning }

  /// This record with the global `defaults` under its own tuning, per key. A default applies
  /// only for a key the family reads and the record's layers leave unset.
  func applying(defaults: ControllerTuning) -> Self {
    let keys = defaults.setKeys.intersection(tuningScope).subtracting(profile.tuning.setKeys)
    guard !keys.isEmpty else { return self }
    var layers = tuningLayers
    for key in keys { layers[key.rawValue] = .global }
    var profile = profile
    profile.tuning = defaults.keeping(keys).overlaid(by: profile.tuning)
    return Self(
      identity: identity,
      document: document,
      fieldLayers: fieldLayers,
      tuningLayers: layers,
      userFile: userFile,
      family: family,
      tuningScope: tuningScope,
      profile: profile
    )
  }

  /// Whether the family reaches the controller through raw USB rather than HID.
  public var usesRawUSB: Bool { profile.usesRawUSB }

  /// Whether the record is a Switch 2 controller without `bluetoothLE`, which OJD reaches only
  /// over USB, because the Bluetooth LE central needs the vibration characteristic.
  public var isSwitch2WithoutBluetoothLE: Bool {
    profile.physicalProtocolID == .nintendoSwitch1 && profile.quirks.contains(.switch2)
      && profile.bluetoothLEVibrationCharacteristic == nil
  }

  /// `user` when a user file adds or patches the record, `bundled` otherwise.
  public var layer: ControllerRecordLayer { userFile == nil ? .bundled : .user }
}

/// One file in the user's controller-record directory, or the directory itself when it cannot be
/// read, and whether OJD could apply it.
public struct ControllerRecordFile: Sendable {
  public let url: URL
  /// The identity the file names, when it could be read.
  public let identity: ControllerIdentity?
  public let operation: ControllerRecordOperation?
  /// Why OJD skipped the file, or nil when it applied it.
  public let problem: String?
}

/// A user record that passed validation, before it is written or applied.
public struct ValidatedControllerRecord: Sendable {
  public let operation: ControllerRecordOperation
  public let record: ControllerRecord

  /// The file name the record must have in the user directory, such as `045e-028e.json`.
  public var fileName: String { ControllerRecordSet.fileName(for: record.identity) }
}

/// Why a user controller record is invalid, in words for the person who wrote it.
public struct ControllerRecordProblem: Error, Equatable, Sendable, CustomStringConvertible {
  public let description: String

  init(_ description: String) { self.description = description }
}

/// The bundled controller catalog with the user's controller records applied.
///
/// A user file that fails validation is skipped and listed in ``userFiles`` with its reason. The
/// bundled catalog must be valid: a release must not ship a broken record.
public struct ControllerRecordSet: Sendable {
  /// The `$schema` that OJD writes into a user record.
  public static let overrideSchemaID =
    "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/"
    + "Resources/Schemas/v1beta1/controller-override.schema.json"
  /// The `$schema` values OJD accepts in a user record. A version that is not here is rejected.
  public static let knownOverrideSchemaIDs: Set<String> = [overrideSchemaID]

  /// The effective record of every identity.
  public let records: [ControllerIdentity: ControllerRecord]
  /// Every `.json` file in the user directory, in file-name order.
  public let userFiles: [ControllerRecordFile]
  /// The global defaults under every record's tuning; none for the bundled catalog alone.
  public let defaults: ControllerDefaults?

  init(
    records: [ControllerIdentity: ControllerRecord],
    userFiles: [ControllerRecordFile],
    defaults: ControllerDefaults? = nil
  ) {
    self.records = records
    self.userFiles = userFiles
    self.defaults = defaults
  }

  /// The user files OJD skipped.
  public var problems: [ControllerRecordFile] { userFiles.filter { $0.problem != nil } }

  /// `~/Library/Application Support/OpenJoystickDriver/Controllers`.
  public static var userDirectory: URL {
    let manager = FileManager.default
    let support =
      manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    return support.appendingPathComponent("OpenJoystickDriver", isDirectory: true)
      .appendingPathComponent("Controllers", isDirectory: true)
  }

  /// The bundled catalog alone.
  public static let bundled: ControllerRecordSet = {
    do { return try loadBundled() } catch {
      fatalError("[DeviceCatalog] Invalid controller catalog: \(error)")
    }
  }()

  /// Makes these records the ones every ``ProtocolDriverRegistry`` binds with.
  ///
  /// Returns the identities whose effective record changed, added, or went away. Devices that
  /// are already bound keep the record they bound with until they are admitted again.
  @discardableResult
  public func activate() -> Set<ControllerIdentity> {
    let catalog = DeviceCatalog(records: self)
    return DeviceCatalog.current.withLock { current in
      defer { current = catalog }
      let identities = Set(current.documents.keys).union(catalog.documents.keys)
      return identities.filter { current.documents[$0] != catalog.documents[$0] }
    }
  }

  /// `vvvv-pppp.json`, the file name of a record for `identity`.
  public static func fileName(for identity: ControllerIdentity) -> String {
    String(format: "%04x-%04x.json", identity.vendorID, identity.productID)
  }

  /// The bundled catalog with every valid `.json` file in `directory` applied. A missing
  /// directory holds no records; one that cannot be read is listed in ``userFiles`` with its
  /// reason. The global defaults in `defaultsFile`, `Defaults.json` beside `directory` unless
  /// given, go under every record's tuning.
  public static func load(
    userDirectory directory: URL = userDirectory,
    defaultsFile: URL? = nil
  ) -> Self {
    let defaults = ControllerDefaults.load(
      from: defaultsFile ?? ControllerDefaults.file(besides: directory)
    )
    let loaded = loadRecords(userDirectory: directory)
    return Self(
      records: loaded.records.mapValues { $0.applying(defaults: defaults.tuning) },
      userFiles: loaded.userFiles,
      defaults: defaults
    )
  }

  private static func loadRecords(userDirectory directory: URL) -> Self {
    let urls: [URL]
    do {
      urls = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    } catch CocoaError.fileReadNoSuchFile {
      urls = []
    } catch {
      let file = ControllerRecordFile(
        url: directory,
        identity: nil,
        operation: nil,
        problem: "cannot read the directory: \(error.localizedDescription)"
      )
      return Self(records: bundled.records, userFiles: [file])
    }
    var records = bundled.records
    var files: [ControllerRecordFile] = []
    for url in urls {
      let file: ControllerRecordFile
      do {
        let validated = try validate(Data(contentsOf: url), file: url)
        let expected = fileName(for: validated.record.identity)
        if url.lastPathComponent == expected {
          records[validated.record.identity] = validated.record
          file = ControllerRecordFile(
            url: url,
            identity: validated.record.identity,
            operation: validated.operation,
            problem: nil
          )
        } else {
          file = ControllerRecordFile(
            url: url,
            identity: validated.record.identity,
            operation: validated.operation,
            problem: "the file name must be \(expected)"
          )
        }
      } catch {
        file = ControllerRecordFile(
          url: url,
          identity: nil,
          operation: nil,
          problem: problemDescription(error)
        )
      }
      files.append(file)
    }
    return Self(records: records, userFiles: files)
  }

  /// Validates one user record against the bundled catalog: the override schema's shape, the
  /// controller contract and its cross-field checks, and the operation's fit with the catalog.
  /// `file` becomes the record's ``ControllerRecord/userFile``.
  public static func validate(_ data: Data, file: URL? = nil) throws -> ValidatedControllerRecord {
    guard let object = try? JSONSerialization.jsonObject(with: data),
      let document = object as? [String: Any]
    else { throw ControllerRecordProblem("the file is not a JSON object") }
    guard let schema = document["$schema"] as? String, knownOverrideSchemaIDs.contains(schema)
    else {
      throw ControllerRecordProblem(
        "$schema must be one of \(knownOverrideSchemaIDs.sorted().joined(separator: ", "))"
      )
    }
    switch document["operation"] as? String {
    case ControllerRecordOperation.add.rawValue:
      try requireKeys(document, ["$schema", "operation", "record"])
      guard let record = document["record"] as? [String: Any] else {
        throw ControllerRecordProblem("record must be an object")
      }
      let decoded = try decode(record)
      guard bundled.records[decoded.identity] == nil else {
        throw ControllerRecordProblem(
          "\(identityText(decoded.identity)) is a bundled controller; use a patch to change it"
        )
      }
      let layers = Dictionary(
        uniqueKeysWithValues: fieldNames(of: record).map { ($0, ControllerRecordLayer.user) }
      )
      return ValidatedControllerRecord(
        operation: .add,
        record: try makeRecord(record, layers: layers, userFile: file)
      )
    case ControllerRecordOperation.patch.rawValue:
      try requireKeys(document, ["$schema", "operation", "vendorID", "productID", "set"])
      guard let vendorID = integer(document["vendorID"]).flatMap(UInt16.init(exactly:)),
        vendorID >= 1, let productID = integer(document["productID"]).flatMap(UInt16.init(exactly:))
      else { throw ControllerRecordProblem("vendorID must be 1...65535 and productID 0...65535") }
      let identity = ControllerIdentity(vendorID: vendorID, productID: productID)
      guard let fields = document["set"] as? [String: Any], !fields.isEmpty,
        Set(fields.keys).isSubset(of: [
          "protocol", "usb", "bluetoothLE", "ownership", "output", "input", "tuning",
        ])
      else {
        throw ControllerRecordProblem(
          "set must hold protocol, usb, bluetoothLE, ownership, output, input, or tuning"
        )
      }
      guard let upstream = bundled.records[identity],
        let base = try JSONSerialization.jsonObject(with: upstream.document) as? [String: Any]
      else {
        throw ControllerRecordProblem(
          "\(identityText(identity)) is not a bundled controller; use an add record"
        )
      }
      var merged = base.merging(fields) { _, patched in patched }
      // A patch names the tuning keys it sets and keeps the bundled record's other keys.
      if let patched = fields["tuning"] as? [String: Any],
        let bundledTuning = base["tuning"] as? [String: Any]
      {
        merged["tuning"] = bundledTuning.merging(patched) { _, value in value }
      }
      // Every protocol field is scoped to its family, so a patch that keeps the family merges
      // into the bundled block (RFC 7396) and keeps the fields it does not name. Its quirks join
      // the bundled quirks, so a patch cannot drop the quirks that select a model's calibration.
      if var patched = fields["protocol"] as? [String: Any],
        let bundledProtocol = base["protocol"] as? [String: Any],
        patched["family"] as? String == bundledProtocol["family"] as? String
      {
        if let bundledQuirks = bundledProtocol["quirks"] as? [String],
          let patchedQuirks = patched["quirks"] as? [String]
        {
          patched["quirks"] = bundledQuirks + patchedQuirks.filter { !bundledQuirks.contains($0) }
        }
        merged["protocol"] = bundledProtocol.merging(patched) { _, value in value }
      }
      guard
        try JSONSerialization.data(withJSONObject: merged, options: .sortedKeys)
          != JSONSerialization.data(withJSONObject: base, options: .sortedKeys)
      else { throw ControllerRecordProblem("the patch changes nothing in the bundled record") }
      var layers = upstream.fieldLayers
      for key in fields.keys { layers[key] = .user }
      var tuningLayers = upstream.tuningLayers
      for key in (fields["tuning"] as? [String: Any] ?? [:]).keys { tuningLayers[key] = .user }
      return ValidatedControllerRecord(
        operation: .patch,
        record: try makeRecord(
          merged,
          layers: layers,
          tuningLayers: tuningLayers,
          userFile: file
        )
      )
    default: throw ControllerRecordProblem("operation must be add or patch")
    }
  }

  /// The bundled records, decoded once per process.
  private static func loadBundled() throws -> Self {
    let urls = (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
      .filter { isRecordFileName($0.lastPathComponent) }.sorted {
        $0.lastPathComponent < $1.lastPathComponent
      }
    guard !urls.isEmpty else { throw ControllerRecordProblem("controller catalog is empty") }
    var records: [ControllerIdentity: ControllerRecord] = [:]
    for url in urls {
      do {
        guard
          let document = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            as? [String: Any]
        else { throw ControllerRecordProblem("not a JSON object") }
        let layers = Dictionary(
          uniqueKeysWithValues: fieldNames(of: document).map { ($0, ControllerRecordLayer.bundled) }
        )
        let record = try makeRecord(document, layers: layers, userFile: nil)
        guard url.lastPathComponent == fileName(for: record.identity) else {
          throw ControllerRecordProblem("filename must be \(fileName(for: record.identity))")
        }
        guard records[record.identity] == nil else {
          throw ControllerRecordProblem("duplicate controller identity")
        }
        records[record.identity] = record
      } catch { throw ControllerRecordProblem("\(url.path): \(problemDescription(error))") }
    }
    return Self(records: records, userFiles: [])
  }

  private static func isRecordFileName(_ name: String) -> Bool {
    guard name.count == 14, name.hasSuffix(".json") else { return false }
    let stem = name.dropLast(5)
    guard stem[stem.index(stem.startIndex, offsetBy: 4)] == "-" else { return false }
    return stem.enumerated().allSatisfy { offset, character in offset == 4 || character.isHexDigit }
  }

  private static func decode(
    _ record: [String: Any]
  ) throws -> (identity: ControllerIdentity, document: ControllerRecordDocument) {
    let data = try JSONSerialization.data(withJSONObject: record)
    let document = try JSONDecoder().decode(ControllerRecordDocument.self, from: data)
    guard let vendorID = UInt16(exactly: document.vendorID),
      let productID = UInt16(exactly: document.productID)
    else { throw ControllerRecordProblem("vendorID must be 1...65535 and productID 0...65535") }
    return (ControllerIdentity(vendorID: vendorID, productID: productID), document)
  }

  private static func makeRecord(
    _ record: [String: Any],
    layers: [String: ControllerRecordLayer],
    tuningLayers: [String: ControllerRecordLayer]? = nil,
    userFile: URL?
  ) throws -> ControllerRecord {
    let decoded = try decode(record)
    let set = decoded.document.tuning.setKeys
    return ControllerRecord(
      identity: decoded.identity,
      document: try JSONSerialization.data(
        withJSONObject: record,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      ),
      fieldLayers: layers,
      tuningLayers: tuningLayers
        ?? Dictionary(
          uniqueKeysWithValues: set.map { ($0.rawValue, layers["tuning"] ?? .bundled) }
        ),
      userFile: userFile,
      family: decoded.document.protocolInfo.protocolID.rawValue,
      tuningScope: Set(
        ControllerTuning.Key.allCases.filter { decoded.document.tuningScopeViolation($0) == nil }
      ),
      profile: try DeviceCatalog.makeRuntimeProfile(decoded.document)
    )
  }

  private static func fieldNames(of record: [String: Any]) -> [String] {
    record.keys.filter { !["$schema", "vendorID", "productID"].contains($0) }
  }

  private static func requireKeys(_ document: [String: Any], _ keys: Set<String>) throws {
    let present = Set(document.keys)
    guard present == keys else {
      let unknown = present.subtracting(keys).sorted()
      let missing = keys.subtracting(present).sorted()
      let parts =
        (unknown.isEmpty ? [] : ["unknown field(s): \(unknown.joined(separator: ", "))"])
        + (missing.isEmpty ? [] : ["missing field(s): \(missing.joined(separator: ", "))"])
      throw ControllerRecordProblem(parts.joined(separator: "; "))
    }
  }

  /// An integer JSON number; booleans and fractions are not integers.
  private static func integer(_ value: Any?) -> Int? {
    // swiftlint:disable:next legacy_objc_type
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
      let integer = Int(exactly: number.doubleValue)
    else { return nil }
    return integer
  }

  private static func identityText(_ identity: ControllerIdentity) -> String {
    String(format: "%04X:%04X", identity.vendorID, identity.productID)
  }

  /// A one-line reason for a decoding or file error, with the JSON path of the field.
  public static func problemDescription(_ error: any Error) -> String {
    func path(_ codingPath: [any CodingKey]) -> String {
      codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
    }
    func located(_ codingPath: [any CodingKey], _ text: String) -> String {
      codingPath.isEmpty ? text : "record.\(path(codingPath)): \(text)"
    }
    switch error {
    case let problem as ControllerRecordProblem: return problem.description
    case DecodingError.dataCorrupted(let context):
      return located(context.codingPath, context.debugDescription)
    case DecodingError.keyNotFound(let key, let context):
      return located(context.codingPath, "missing field \(key.stringValue)")
    case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
      return located(context.codingPath, context.debugDescription)
    default: return error.localizedDescription
    }
  }
}
