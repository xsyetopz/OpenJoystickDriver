public import Foundation

/// Where one part of an effective controller record comes from.
///
/// The cases are in precedence order, lowest first: a later layer wins over an earlier one.
public enum ControllerRecordLayer: String, Codable, CaseIterable, Sendable {
  /// OJD's built-in default, used when no other layer sets a value.
  case driver = "Driver"
  /// The signed catalog in the app bundle, with its built-in patches.
  case bundled = "Bundled"
  /// A file of an installed mod package.
  case package = "Package"
  /// The user's `all` patch, `all.patch.plist`: the first patch of the user layer.
  case global = "Global"
  /// A file in the user's controller-record directory.
  case user = "User"
  /// The active remapping profile.
  case profile = "Profile"
}

/// The kind of a user controller record file.
public enum ControllerRecordOperation: String, Codable, Sendable {
  /// A Controller file: a record for a model the bundled catalog does not have.
  case add = "Add"
  /// A ControllerPatch file: a merge patch over the records its selector names.
  case patch = "Patch"
}

/// One effective controller record: a bundled record, a Controller file that adds one, or a
/// record with package and user patches applied.
public struct ControllerRecord: Sendable {
  /// The controller model the record describes.
  public let model: ControllerModelID
  /// The merged record as a `controller.schema.json` document, in the record file text of
  /// ``OrderedJSON/plistData()``.
  public let text: String
  /// The layer of each top-level field of `text`, except `apiVersion`, `kind`, `vendorID`, and
  /// `productID`.
  public let fieldLayers: [String: ControllerRecordLayer]
  /// The layer of each effective `tuning` key, by its JSON name: `Bundled`, `User`, or `Global`.
  ///
  /// A key no layer sets is absent, and the driver default applies.
  public let tuningLayers: [String: ControllerRecordLayer]
  /// The user file that adds or patches this record, or nil for a bundled record.
  ///
  /// An `all` patch is not listed here.
  public let userFile: URL?
  /// The file of an installed package that adds or patches this record, or nil when no package
  /// does.
  ///
  /// A user file over it wins, and ``layer`` names the user.
  public let packageFile: URL?
  /// The serial number that this model's firmware reports when it has none of its own; nil when
  /// the record names none.
  public let placeholderSerial: String?
  /// The protocol family.
  public let protocolID: PhysicalProtocolID
  /// The protocol family's name, such as `XboxGIP`.
  public var family: String { protocolID.rawValue }
  /// The tuning keys this record's family reads.
  let tuningScope: Set<ControllerTuning.Key>
  /// The runtime profile built from the record.
  let profile: DeviceRuntimeProfile

  /// The effective tuning: the global defaults under the record's own values, per key.
  public var tuning: ControllerTuning { profile.tuning }

  /// Whether the family reaches the controller through raw USB rather than HID.
  public var usesRawUSB: Bool { profile.usesRawUSB }

  /// How OJD reaches the controller: the record route, else the family.
  public var accessRoute: ControllerAccessRoute { profile.accessRoute }

  /// Who serves the controller: `system` unless a layer sets `ojd`.
  public var server: ControllerServer { profile.server }

  /// The route the record asks for; nil leaves it to the family.
  public var route: ControllerRecordRoute? { profile.route }

  /// Whether Apple's own driver extension holds the controller's USB interface, so only OJD's USB
  /// extension can open it.
  public var heldByAppleDriver: Bool { profile.heldByAppleDriver }

  /// Whether the record is a Switch 2 controller without `bluetoothLE`, which OJD reaches only
  /// over USB, because the Bluetooth LE central needs the vibration characteristic.
  public var isSwitch2WithoutBluetoothLE: Bool {
    profile.physicalProtocolID == .nintendoSwitch2
      && profile.bluetoothLEVibrationCharacteristic == nil
  }

  /// The file of the highest layer that adds or patches this record, or nil for a bundled one.
  public var file: URL? { userFile ?? packageFile }

  /// `User` when a user file adds or patches the record, else `Package` when a package does,
  /// `Bundled` otherwise.
  public var layer: ControllerRecordLayer {
    userFile != nil ? .user : packageFile != nil ? .package : .bundled
  }
}

/// One file in the user's controller-record directory, or the directory itself when it cannot be
/// read, and whether OJD could apply it.
public struct ControllerRecordFile: Sendable {
  /// The location of the file.
  public let url: URL
  /// The model the file names, when it could be read.
  public let model: ControllerModelID?
  /// The operation the file performs; nil when the file could not be read.
  public let operation: ControllerRecordOperation?
  /// Why OJD skipped the file, or nil when it applied it.
  public let problem: String?
}

/// A user record file that passed validation, before it is written or applied.
public struct ValidatedControllerRecord: Sendable {
  /// The operation the file performs.
  public let operation: ControllerRecordOperation
  /// The record the file gives: the Controller file's own, or the patched record.
  ///
  /// Nil for an `all` patch, which applies to every record.
  public let record: ControllerRecord?
  /// The selector of a patch file, or nil for a Controller file.
  public let selector: ControllerPatch.Selector?

  /// The file name the record file must have in the user directory, such as `045e-028e.plist` for a
  /// Controller file and `045e-028e.patch.plist` for a patch.
  public var fileName: String {
    selector?.fileName ?? record.map { ControllerRecordSet.fileName(for: $0.model) } ?? ""
  }
}

extension ControllerRecord {
  /// ``text`` as UTF-8, the bytes of a record file.
  public var document: Data { Data(text.utf8) }
}

/// Why a controller record, patch or related document, such as a virtual device, is invalid.
///
/// It carries ``ErrorCode/invalidControllerRecord``. ``description`` leaves the code out.
public struct ControllerRecordProblem: Error, Equatable, Sendable, CustomStringConvertible {
  /// The reason the record or file was rejected.
  public let description: String
  /// The error code of the rejection.
  public let code: ErrorCode
  /// The catalog key of the localized message for this rule, or nil when the rule has none yet.
  ///
  /// The message takes the file as `%1$@`, then ``arguments`` from `%2$@`.
  public let key: String?
  /// The values that the localized message names after the file, such as a file name.
  public let arguments: [String]

  /// Creates a problem from an error code and a description.
  init(code: ErrorCode, _ description: String) {
    self.code = code
    self.description = description
    self.key = nil
    self.arguments = []
  }

  /// Creates a problem that has its own localized message under `key`.
  ///
  /// `description` is the English reason that stays stable for the repository tool.
  init(code: ErrorCode, key: String, arguments: [String] = [], _ description: String) {
    self.code = code
    self.description = description
    self.key = key
    self.arguments = arguments
  }

  /// The decoding context that reports this problem at `codingPath`, keeping the problem so that
  /// ``ControllerRecordSet/problemDescription(_:includingCode:document:localization:file:)`` can
  /// read its localized message.
  func context(at codingPath: [any CodingKey]) -> DecodingError.Context {
    DecodingError.Context(
      codingPath: codingPath,
      debugDescription: description,
      underlyingError: self
    )
  }

  /// The message in `localization`, with `file` as the file it names, or ``description`` when the
  /// rule has no localized message.
  func localizedDescription(_ localization: Localization, file: String?) -> String {
    guard let key else { return description }
    let named = file ?? localization.string("error.E5007.thisFile")
    return localization.formatted(key, arguments: [named] + arguments)
  }
}

/// The bundled controller catalog with the user's controller records applied.
///
/// A user file that fails validation is skipped and listed in ``userFiles`` with its reason. The
/// bundled catalog must be valid: a release must not ship a broken record.
public struct ControllerRecordSet: Sendable {
  /// The effective record of every model.
  public let records: [ControllerModelID: ControllerRecord]
  /// Every `.plist` file in the user directory except `all.patch.plist`, in file-name order, then
  /// the record files of the installed packages in package-name order.
  public let userFiles: [ControllerRecordFile]
  /// The user's `all` patch, applied to every record; none for the bundled catalog alone.
  public let defaults: ControllerDefaults?

  /// Creates a set from the effective records, the user files and the user's `all` patch.
  init(
    records: [ControllerModelID: ControllerRecord],
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
    MacOSDataDirectory().url(for: .applicationData)
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
  /// Returns the models whose effective record changed, added, or went away. Devices that
  /// are already bound keep the record they bound with until they are admitted again.
  @discardableResult
  public func activate() -> Set<ControllerModelID> {
    let catalog = DeviceCatalog(records: self)
    return DeviceCatalog.current.withLock { current in
      defer { current = catalog }
      let models = Set(current.documents.keys).union(catalog.documents.keys)
      return models.filter { current.documents[$0] != catalog.documents[$0] }
    }
  }

  /// `vvvv-pppp.plist`, the file name of a record for `model`.
  public static func fileName(for model: ControllerModelID) -> String {
    unsafe String(format: "%04x-%04x.plist", model.vendorID, model.productID)
  }

  /// The bundled records, decoded once per process.
  private static func loadBundled() throws -> Self {
    let urls = (Bundle.module.urls(forResourcesWithExtension: "plist", subdirectory: nil) ?? [])
      .filter { isRecordFileName($0.lastPathComponent) }
    guard !urls.isEmpty else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.record.catalogEmpty",
        "controller catalog is empty"
      )
    }
    let catalog = loadCatalog(urls)
    if let problem = catalog.problems.first { throw bundledFailure(problem) }
    return Self(records: catalog.records, userFiles: [])
  }

  /// The failure that a bundled record with `problem` raises: the file, then the problem's code
  /// and reason.
  static func bundledFailure(_ problem: RepositoryProblem) -> ControllerRecordProblem {
    ControllerRecordProblem(
      code: .invalidControllerRecord,
      "\(problem.file): \(problem.code.rawValue): \(problem.message)"
    )
  }

  /// The records of the Controller files `urls` in file-name order, and a problem for each file
  /// that is not a valid record of the catalog: one that fails the record rules, whose file name is
  /// not its record's ``fileName(for:)``, or whose identity an earlier file holds.
  ///
  /// The bundled catalog and ``RepositoryValidation/records(in:)`` load through this check.
  static func loadCatalog(
    _ urls: [URL]
  ) -> (records: [ControllerModelID: ControllerRecord], problems: [RepositoryProblem]) {
    var loaded: [ControllerModelID: ControllerRecord] = [:]
    var files: [ControllerModelID: String] = [:]
    var rejected: [RepositoryProblem] = []
    let sortedURLs = urls.sorted {
      ($0.lastPathComponent, $0.path) < ($1.lastPathComponent, $1.path)
    }
    for url in sortedURLs {
      do {
        let data = try RepositoryProblem.read(url)
        let document = try ordered(data, file: url.lastPathComponent)
        let layers = Dictionary(
          uniqueKeysWithValues: fieldNames(of: document).map { ($0, ControllerRecordLayer.bundled) }
        )
        let record = try makeRecord(document, layers: layers)
        guard url.lastPathComponent == fileName(for: record.model) else {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            key: "error.E5007.record.fileName",
            arguments: [fileName(for: record.model)],
            "filename must be \(fileName(for: record.model))"
          )
        }
        if let first = files[record.model] {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            key: "error.E5007.record.duplicateIdentity",
            arguments: ["\(record.model)", first],
            "duplicate controller identity \(record.model): \(first) already holds it"
          )
        }
        files[record.model] = url.path
        loaded[record.model] = record
      } catch {
        rejected.append(RepositoryProblem(file: url.path, error: error, document: "record"))
      }
    }
    return (loaded, rejected)
  }

  /// Whether `name` is `vvvv-pppp.plist` with hex digits.
  private static func isRecordFileName(_ name: String) -> Bool {
    guard name.count == 15, name.hasSuffix(".plist") else { return false }
    let stem = name.dropLast(6)
    guard stem[stem.index(stem.startIndex, offsetBy: 4)] == "-" else { return false }
    return stem.enumerated().allSatisfy { offset, character in offset == 4 || character.isHexDigit }
  }

  /// The model and the typed document of `record`.
  ///
  /// The typed document is read from the Foundation view of `record`
  /// (``OrderedJSON/foundationValue()``) and is never written back as text.
  static func decode(
    _ record: OrderedJSON
  ) throws -> (model: ControllerModelID, document: ControllerRecordDocument) {
    let data: Data
    do { data = try JSONSerialization.data(withJSONObject: record.foundationValue()) } catch {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.record.unwritableValue",
        arguments: [error.localizedDescription],
        error.localizedDescription
      )
    }
    let document = try JSONDecoder().decode(ControllerRecordDocument.self, from: data)
    guard let vendorID = UInt16(exactly: document.vendorID),
      let productID = UInt16(exactly: document.productID)
    else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.record.idRange",
        "vendorID must be 1...65535 and productID 0...65535"
      )
    }
    return (ControllerModelID(vendorID: vendorID, productID: productID), document)
  }

  /// The members of the XML property list `data`, in sorted order; `file` names it in a refusal.
  ///
  /// Any other form, and a `date` or `data` value, is `invalidDocumentForm`.
  static func ordered(_ data: Data, file: String) throws -> OrderedJSON {
    try OrderedJSON(document: data, file: file)
  }

  /// The record for `record`, whose ``ControllerRecord/text`` is `record` as it is: members in
  /// its order and numbers as written.
  static func makeRecord(
    _ record: OrderedJSON,
    layers: [String: ControllerRecordLayer],
    tuningLayers: [String: ControllerRecordLayer]? = nil,
    userFile: URL? = nil,
    packageFile: URL? = nil
  ) throws -> ControllerRecord {
    let decoded = try decode(record)
    let set = decoded.document.tuning.setKeys
    return ControllerRecord(
      model: decoded.model,
      text: String(bytes: try record.plistData(), encoding: .utf8) ?? "",
      fieldLayers: layers,
      tuningLayers: tuningLayers
        ?? Dictionary(
          uniqueKeysWithValues: set.map { ($0.rawValue, layers["tuning"] ?? .bundled) }
        ),
      userFile: userFile,
      packageFile: packageFile,
      placeholderSerial: decoded.document.placeholderSerial,
      protocolID: decoded.document.protocolInfo.protocolID,
      tuningScope: Set(
        ControllerTuning.Key.allCases.filter { decoded.document.tuningScopeViolation($0) == nil }
      ),
      profile: try DeviceCatalog.makeRuntimeProfile(decoded.document)
    )
  }

  /// The member names of `record` other than `apiVersion`, `kind`, `vendorID` and `productID`.
  static func fieldNames(of record: OrderedJSON) -> [String] {
    (record.members ?? []).map(\.key).filter {
      !["apiVersion", "kind", "vendorID", "productID"].contains($0)
    }
  }

  /// An integer JSON number; booleans and fractions are not integers.
  static func integer(_ value: Any?) -> Int? {
    // swiftlint:disable:next legacy_objc_type
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
      let integer = Int(exactly: number.doubleValue)
    else { return nil }
    return integer
  }

  /// The error code of a record that is refused: ``ErrorCode/unsupportedAPIVersion`` for its
  /// `apiVersion`, and ``ErrorCode/invalidControllerRecord`` for any other failed rule, including a
  /// record whose values ``OrderedJSON`` cannot write.
  ///
  /// Nil when `error` is not about the record's content, such as a file that cannot be read.
  public static func problemCode(_ error: any Error) -> ErrorCode? {
    switch error {
    case let problem as DocumentHeaderProblem: problem.code ?? .invalidControllerRecord
    case let problem as ControllerRecordProblem: problem.code
    case let problem as DocumentCoderError: problem.code
    case is DecodingError, is OrderedJSON.Problem: .invalidControllerRecord
    default: nil
    }
  }

  /// A one-line reason for a decoding or file error, with the JSON path of the field.
  ///
  /// A reason that has an error code leads with it, such as `E5001: `, because a reason is a plain
  /// string where it is listed. A caller that reports the code itself passes `includingCode:
  /// false`. A field path leads with `document`, the noun for the kind of file that was decoded.
  ///
  /// With `localization`, a rule that has its own message reads in that language and names `file`,
  /// the file that failed, or "this record file" when `file` is nil. Without it the reason is the
  /// English ``ControllerRecordProblem/description``.
  public static func problemDescription(
    _ error: any Error,
    includingCode: Bool = true,
    document: String,
    localization: Localization? = nil,
    file: String? = nil
  ) -> String {
    func path(_ codingPath: [any CodingKey]) -> String {
      codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
    }
    func located(_ codingPath: [any CodingKey], _ text: String) -> String {
      codingPath.isEmpty ? text : "\(document).\(path(codingPath)): \(text)"
    }
    switch error {
    case let problem as ControllerRecordProblem:
      guard let localization else { return problem.description }
      return problem.localizedDescription(localization, file: file)
    case let problem as DocumentCoderError: return problem.description
    case let problem as DocumentHeaderProblem:
      return includingCode ? problem.description : problem.message
    case DecodingError.dataCorrupted(let context):
      if let localization, let problem = context.underlyingError as? ControllerRecordProblem,
        problem.key != nil
      {
        return problem.localizedDescription(localization, file: file)
      }
      return located(context.codingPath, context.debugDescription)
    case DecodingError.keyNotFound(let key, let context):
      return located(context.codingPath, "missing field \(key.stringValue)")
    case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
      return located(context.codingPath, context.debugDescription)
    default: return error.localizedDescription
    }
  }
}
