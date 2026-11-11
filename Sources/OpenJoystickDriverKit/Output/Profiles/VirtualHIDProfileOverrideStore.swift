public import Foundation

/// Why the persona directory cannot be read.
public enum VirtualHIDProfileOverrideError: Error, Equatable, Sendable {
  /// The directory exists but cannot be listed, created, or written.
  case unreadableDirectory(String)
  /// The persona file at this path sets its own identity or comes from a package, so a reset
  /// leaves it in place.
  case keptFile(String)
}

/// One persona: a built-in report descriptor and, optionally, the identity published over it.
public struct VirtualPersona: Equatable, Sendable {
  /// The identity strings, IDs, and glyph family a user defined over the descriptor.
  public struct Identity: Equatable, Sendable {
    /// The USB vendor ID.
    public let vendorID: UInt16
    /// The USB product ID.
    public let productID: UInt16
    /// The version number; nil when the persona sets none.
    public let versionNumber: Int?
    /// The product name.
    public let productName: String
    /// The manufacturer name.
    public let manufacturer: String
    /// The glyph family of the published product.
    public let glyphFamily: VirtualIdentityGlyphFamily
  }

  /// The built-in descriptor that the persona uses.
  public let descriptor: VirtualHIDProfileID
  /// Nil for a persona that only selects the descriptor, which `ojd virtual` writes.
  public let identity: Identity?
}

/// One file of the `VirtualDevices` directory or of a package, or the folder that OJD does not
/// read, and whether OJD applied it.
public struct VirtualPersonaFile: Equatable, Sendable {
  /// The file or folder.
  public let url: URL
  /// Why OJD skipped the file, or nil when it applied it.
  public let problem: String?
}

/// Per-controller-model and per-unit personas, stored as `VirtualDevices/<id>.plist` files that
/// follow `virtual-device.schema.json`.
///
/// A file matches a VID:PID model, or one unit of it (see ``ControllerPortKey``). A unit's persona
/// wins over its model's. A file that fails validation, or repeats the match of an earlier file in
/// file-name order, is skipped and listed in ``problems``. A missing directory holds no personas.
/// A folder named ``unreadFolderName`` beside the directory is not read, and ``files`` lists it
/// with the reason when it holds a visible file, so that the files a user keeps there are not
/// ignored without a word.
/// `set` writes `vvvv-pppp.plist` or `vvvv-pppp-<unit>.plist`, and keeps the identity of a persona
/// that already matches.
public struct VirtualHIDProfileOverrideStore: Sendable {
  /// The `kind` of a persona file.
  public static let kind = VirtualDevice.kind

  /// `~/Library/Application Support/OpenJoystickDriver/VirtualDevices`.
  public static var userDirectory: URL {
    ControllerRecordSet.userDirectory.deletingLastPathComponent()
      .appendingPathComponent(directoryName, isDirectory: true)
  }

  /// The name of the folder of `VirtualDevice` files, in the user data folder and in a package.
  public static let directoryName = "VirtualDevices"

  /// The folder name `Personas`, which OJD does not read.
  ///
  /// The concept is a persona, but the files are `VirtualDevice` documents and live in
  /// ``directoryName``; ``files`` lists this folder when it holds a visible file, so that its files
  /// do not go unnoticed.
  public static let unreadFolderName = "Personas"

  /// Formats the messages about files.
  private static let localization = Localization()

  /// A controller model, or one unit of it when `unit` is set.
  struct Model: Hashable {
    /// The USB vendor ID of the controller.
    let vendorID: UInt16
    /// The USB product ID of the controller.
    let productID: UInt16
    /// The unit ID of one controller of the model; nil for the whole model.
    var unit: String?

    /// The name of the persona file: `vvvv-pppp.plist`, with `-<unit>` before the extension for a
    /// unit.
    var fileName: String {
      unsafe String(format: "%04x-%04x", vendorID, productID) + (unit.map { "-\($0)" } ?? "")
        + ".plist"
    }
  }

  /// A persona and the file it came from.
  private struct Found {
    /// The persona.
    let persona: VirtualPersona
    /// The file that holds the persona.
    let url: URL
    /// Whether an installed package holds the file.
    ///
    /// A package file is never written or removed.
    var fromPackage = false
  }

  /// The personas and files that a load found.
  private struct Loaded {
    /// The personas by model.
    var personas: [Model: Found] = [:]
    /// Every file seen, with the reason it was skipped.
    var files: [VirtualPersonaFile] = []
  }

  /// The directory of the persona files.
  private let directory: URL
  /// The installed packages, whose personas apply too.
  private let packages: ModPackageStore

  /// The store of `directory`, with the personas of the packages installed in the `Packages`
  /// folder beside it, or in `packagesDirectory`, under it. `runningVersion` is the OJD version
  /// that the `requires` of a package is checked against; nil means the running one.
  public init(
    directory: URL = Self.userDirectory,
    packagesDirectory: URL? = nil,
    runningVersion: String? = nil
  ) {
    self.directory = directory
    packages = ModPackageStore(
      directory: packagesDirectory ?? ModPackageStore.directory(besides: directory),
      runningVersion: runningVersion
    )
  }

  /// Why the directory cannot be read; nil when it is absent or readable.
  public var loadError: VirtualHIDProfileOverrideError? {
    if case .failure(let error) = load() { return error }
    return nil
  }

  /// Every file in the directory, in file-name order, with the reason OJD skipped it, then the
  /// ``unreadFolderName`` folder beside the directory when it holds a visible file.
  public var files: [VirtualPersonaFile] {
    let unread = unreadFolder.map { [$0] } ?? []
    if case .success(let loaded) = load() { return loaded.files + unread }
    return unread
  }

  /// The ``unreadFolderName`` folder beside the directory, with the reason it is not read; nil
  /// when there is no such folder or it holds no visible file.
  private var unreadFolder: VirtualPersonaFile? {
    let url = directory.deletingLastPathComponent()
      .appendingPathComponent(Self.unreadFolderName, isDirectory: true)
    let contents = try? FileManager.default.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: nil,
      options: .skipsHiddenFiles
    )
    guard contents?.isEmpty == false else { return nil }
    return VirtualPersonaFile(
      url: url,
      problem: Self.localization.formatted(
        "status.virtualDeviceFolderNotRead",
        arguments: [directory.path]
      )
    )
  }

  /// The files OJD skipped.
  public var problems: [VirtualPersonaFile] { files.filter { $0.problem != nil } }

  /// The persona for one controller: the one for `unit`, else the one for its model; nil when it
  /// selects automatically.
  public func persona(vendorID: UInt16, productID: UInt16, unit: String? = nil) -> VirtualPersona? {
    guard case .success(let loaded) = load() else { return nil }
    if let unit,
      let found = loaded.personas[Model(vendorID: vendorID, productID: productID, unit: unit)]
    {
      return found.persona
    }
    return loaded.personas[Model(vendorID: vendorID, productID: productID)]?.persona
  }

  /// The descriptor of ``persona(vendorID:productID:unit:)``.
  public func override(
    vendorID: UInt16,
    productID: UInt16,
    unit: String? = nil
  ) -> VirtualHIDProfileID? {
    persona(vendorID: vendorID, productID: productID, unit: unit)?.descriptor
  }

  /// The descriptor stored for exactly this model, or this unit when `unit` is set.
  public func storedOverride(
    vendorID: UInt16,
    productID: UInt16,
    unit: String?
  ) -> VirtualHIDProfileID? {
    guard case .success(let loaded) = load() else { return nil }
    return loaded.personas[Model(vendorID: vendorID, productID: productID, unit: unit)]?
      .persona.descriptor
  }

  /// Stores `profile` as the descriptor of one controller model, or of one unit of it.
  ///
  /// - Throws: The load error while the directory cannot be read or written.
  public func set(
    _ profile: VirtualHIDProfileID,
    vendorID: UInt16,
    productID: UInt16,
    unit: String? = nil
  ) throws(VirtualHIDProfileOverrideError) {
    let model = Model(vendorID: vendorID, productID: productID, unit: unit)
    let existing = try load().get().personas[model]
    if existing?.persona.descriptor == profile { return }
    var match: [String: Any] = ["vendorID": Int(vendorID), "productID": Int(productID)]
    match["unit"] = unit
    var document: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": Self.kind, "match": match,
      "persona": profile.rawValue,
    ]
    if let identity = existing?.persona.identity {
      var fields: [String: Any] = [
        "vendorID": Int(identity.vendorID), "productID": Int(identity.productID),
        "productName": identity.productName, "manufacturer": identity.manufacturer,
      ]
      fields["version"] = identity.versionNumber
      document["identity"] = fields
      document["labels"] = identity.glyphFamily.rawValue
    }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try DocumentCoder.write(document).write(
        to: existing.flatMap { $0.fromPackage ? nil : $0.url }
          ?? directory.appendingPathComponent(model.fileName),
        options: .atomic
      )
    } catch { throw .unreadableDirectory(error.localizedDescription) }
  }

  /// Returns one controller model, or one unit of it, to automatic selection by removing its
  /// descriptor-only persona file.
  ///
  /// Resetting a unit leaves its model's persona in effect.
  ///
  /// - Throws: The load error while the directory cannot be read or written, and
  ///   ``VirtualHIDProfileOverrideError/keptFile(_:)`` for a persona with a custom identity or
  ///   from a package, which only an edit or a removal of its file changes.
  public func reset(
    vendorID: UInt16,
    productID: UInt16,
    unit: String? = nil
  ) throws(VirtualHIDProfileOverrideError) {
    let loaded = try load().get()
    guard let found = loaded.personas[Model(vendorID: vendorID, productID: productID, unit: unit)]
    else { return }
    guard found.persona.identity == nil, !found.fromPackage else { throw .keptFile(found.url.path) }
    do { try FileManager.default.removeItem(at: found.url) } catch {
      throw .unreadableDirectory(error.localizedDescription)
    }
  }

  /// Removes every descriptor-only persona file of the `VirtualDevices` directory.
  ///
  /// Package files and files OJD skipped stay.
  ///
  /// - Returns: The paths of the user files that set their own identity, which stay, and of the
  ///   files that could not be removed.
  /// - Throws: The load error while the directory cannot be read.
  @discardableResult
  public func resetAll() throws(VirtualHIDProfileOverrideError) -> [String] {
    let loaded = try load().get()
    var kept: [String] = []
    for found in loaded.personas.values where !found.fromPackage {
      guard found.persona.identity == nil else {
        kept.append(found.url.path)
        continue
      }
      do { try FileManager.default.removeItem(at: found.url) } catch { kept.append(found.url.path) }
    }
    return kept.sorted()
  }

  /// Loads the user files, then the files of the installed packages.
  private func load() -> Result<Loaded, VirtualHIDProfileOverrideError> {
    loadUserFiles().map { user in
      var loaded = user
      addPackageFiles(to: &loaded)
      return loaded
    }
  }

  /// Adds the personas of the installed packages, in package-name order.
  ///
  /// A package that cannot be used, such as one whose `requires` leaves out the running version,
  /// adds none, and its `mod.plist` is listed with the reason. A persona whose match a user file or
  /// an earlier package already holds is skipped and listed with that reason.
  private func addPackageFiles(to loaded: inout Loaded) {
    for package in packages.list() {
      if let problem = package.problem {
        loaded.files.append(
          VirtualPersonaFile(
            url: package.directory.appendingPathComponent(ModPackageManifest.fileName),
            problem: problem
          )
        )
        continue
      }
      for file in package.manifest?.virtualDevices.sorted() ?? [] {
        let url = package.directory.appendingPathComponent("\(Self.directoryName)/\(file)")
        do {
          let (model, persona) = try Self.parse(Data(contentsOf: url))
          if let first = loaded.personas[model] {
            let owner = first.fromPackage ? "package file " : "user file "
            throw ControllerRecordProblem(
              code: .invalidControllerRecord,
              key: first.fromPackage
                ? "error.E5007.virtualDevice.matchTakenByPackageFile"
                : "error.E5007.virtualDevice.matchTakenByUserFile",
              arguments: [first.url.lastPathComponent],
              "same match as \(owner)\(first.url.lastPathComponent)"
            )
          }
          loaded.personas[model] = Found(persona: persona, url: url, fromPackage: true)
          loaded.files.append(VirtualPersonaFile(url: url, problem: nil))
        } catch {
          loaded.files.append(
            VirtualPersonaFile(
              url: url,
              problem: ControllerRecordSet.problemDescription(error, document: "virtualDevice")
            )
          )
        }
      }
    }
  }

  /// Loads the persona files of the directory in file-name order; a missing directory holds none.
  private func loadUserFiles() -> Result<Loaded, VirtualHIDProfileOverrideError> {
    let urls: [URL]
    do {
      urls = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      ).filter { $0.pathExtension == "plist" }.sorted {
        $0.lastPathComponent < $1.lastPathComponent
      }
    } catch CocoaError.fileReadNoSuchFile {
      return .success(Loaded())
    } catch { return .failure(.unreadableDirectory(error.localizedDescription)) }
    var loaded = Loaded()
    for url in urls {
      do {
        let (model, persona) = try Self.parse(Data(contentsOf: url))
        if let first = loaded.personas[model] {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            key: "error.E5007.virtualDevice.matchTakenByUserFile",
            arguments: [first.url.lastPathComponent],
            "same match as \(first.url.lastPathComponent)"
          )
        }
        loaded.personas[model] = Found(persona: persona, url: url)
        loaded.files.append(VirtualPersonaFile(url: url, problem: nil))
      } catch {
        loaded.files.append(
          VirtualPersonaFile(
            url: url,
            problem: ControllerRecordSet.problemDescription(error, document: "virtualDevice")
          )
        )
      }
    }
    return .success(loaded)
  }

  /// Decodes one `virtual-device.schema.json` document that selects a persona.
  ///
  /// - Throws: The error of decoding the document, or `ControllerRecordProblem` when the document
  ///   holds no `match`.
  static func parse(_ data: Data) throws -> (Model, VirtualPersona) {
    let device = try VirtualDevice.decode(data, source: .unnamed, requiresMatch: true)
    guard let model = device.match else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.virtualDevice.matchRequired",
        "the file must hold match"
      )
    }
    let identity = device.identity.map { identity in
      VirtualPersona.Identity(
        vendorID: identity.vendorID,
        productID: identity.productID,
        versionNumber: identity.versionNumber,
        productName: identity.productName,
        manufacturer: identity.manufacturer,
        glyphFamily: device.labels ?? VirtualDevice.definition(of: device.persona).labels
          ?? .generic
      )
    }
    return (model, VirtualPersona(descriptor: device.persona, identity: identity))
  }
}
