import Foundation

/// What a set of package or user files covers: controller identities, virtual devices, profiles,
/// and protocol descriptions.
private struct ModPackageClaims {
  /// The `Controller` and `ControllerPatch` file names.
  var controllerFiles: Set<String> = []
  /// The `VirtualDevice` file names.
  var virtualDevices: Set<String> = []
  /// The protocol description file names.
  var protocolFiles: Set<String> = []
  /// The profile UUIDs.
  var profileIDs: Set<UUID> = []
  /// The profile names, lowercased.
  var profileNames: Set<String> = []

  /// Records a profile, and returns false when this set already holds its UUID or name.
  mutating func add(_ profile: RemappingProfile) -> Bool {
    let name = profile.name.lowercased(with: Locale(identifier: "en_US_POSIX"))
    return profileIDs.insert(profile.id).inserted && profileNames.insert(name).inserted
  }

  /// The first item that both sets cover, or nil.
  func clash(with other: Self) -> String? {
    if let file = controllerFiles.intersection(other.controllerFiles).min() {
      return "Controllers/\(file)"
    }
    if let file = virtualDevices.intersection(other.virtualDevices).min() {
      return "VirtualDevices/\(file)"
    }
    if let file = protocolFiles.intersection(other.protocolFiles).min() {
      return "Protocols/\(file)"
    }
    if let id = profileIDs.intersection(other.profileIDs).min(by: { $0.uuidString < $1.uuidString })
    {
      return "profile \(id.uuidString)"
    }
    if let name = profileNames.intersection(other.profileNames).min() {
      return "profile named \(name)"
    }
    return nil
  }
}

extension ModPackageStore {
  /// Checks the package in `folder`: its manifest, that it runs on this version, that its files are
  /// the listed ones and valid, and that none clashes with the user's files or another installed
  /// package.
  ///
  /// A package of the same name is the one an install replaces, so it is not a clash.
  ///
  /// - Returns: The manifest.
  /// - Throws: ``ModPackageError`` with the E4xxx code of the first problem.
  @discardableResult
  public func validate(_ folder: URL) throws -> ModPackageManifest {
    try Self.checkLayout(of: folder)
    let manifest = try Self.manifest(in: folder)
    if let problem = requiresProblem(of: manifest) { throw problem }
    let claims = try Self.checkedClaims(of: folder, manifest)
    let user = userRoot
    var holders: [(label: String, claims: ModPackageClaims)] = [
      ("your own files", Self.userClaims(user))
    ]
    // A package that cannot be used, such as one whose `requires` leaves out this version, holds
    // nothing, so it does not block its replacement or another package.
    for other in list() where other.name != manifest.name && other.problem == nil {
      if let held = other.manifest {
        holders.append(("package \(other.name)", Self.claims(of: other.directory, held)))
      }
    }
    for holder in holders {
      if let item = claims.clash(with: holder.claims) {
        throw ModPackageError(.packageClash, "\(item) clashes with \(holder.label)")
      }
    }
    return manifest
  }

  /// The folder that holds the user's `Controllers`, `VirtualDevices`, `Profiles` and `Protocols`
  /// folders.
  private var userRoot: URL { directory.deletingLastPathComponent() }

  /// The E4002 refusal of `manifest` on the running version, or nil when its `requires` admits that
  /// version.
  ///
  /// A running version that is not a SemVer version is refused.
  func requiresProblem(of manifest: ModPackageManifest) -> ModPackageError? {
    guard let running = SemanticVersion(runningVersion) else {
      return ModPackageError(
        .requiresExcludesVersion,
        "the running version \(runningVersion) is not a SemVer version"
      )
    }
    guard manifest.requires.admits(running) else {
      let range =
        "\(manifest.requires.minimum)"
        + (manifest.requires.below.map { " up to \($0)" } ?? " or later")
      return ModPackageError(
        .requiresExcludesVersion,
        "\(manifest.name) requires \(range), and this is \(runningVersion)"
      )
    }
    return nil
  }

  /// The claims of `folder`, after every listed file is present and valid and no file is unlisted.
  private static func checkedClaims(
    of folder: URL,
    _ manifest: ModPackageManifest
  ) throws -> ModPackageClaims {
    var claims = ModPackageClaims()
    let kinds = [
      ("Controllers", manifest.controllers + manifest.patches), ("Profiles", manifest.profiles),
      ("VirtualDevices", manifest.virtualDevices), ("Protocols", manifest.protocols),
    ]
    for (kind, listed) in kinds {
      let present = Set(
        (try? FileManager.default.contentsOfDirectory(
          at: folder.appendingPathComponent(kind),
          includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles]
        ))?.filter { !isScript($0) }.map(\.lastPathComponent) ?? []
      )
      if let file = Set(listed).subtracting(present).min() {
        throw ModPackageError(.invalidPackageContent, "\(kind)/\(file) is listed and missing")
      }
      if let file = present.subtracting(listed).min() {
        throw ModPackageError(.invalidPackageContent, "\(kind)/\(file) is not listed in mod.plist")
      }
    }
    // A Controller file may name a family that the package defines, so those are read first.
    var families: [DocumentedProtocolFamily] = []
    for file in manifest.protocols {
      do {
        families.append(
          try DocumentedProtocolFamilies.read(
            folder.appendingPathComponent("Protocols/\(file)"),
            package: manifest.name
          )
        )
      } catch {
        throw ModPackageError(
          error.code == .unsupportedAPIVersion ? .unsupportedAPIVersion : .invalidPackageContent,
          "Protocols/\(file): \(error.detail)"
        )
      }
      claims.protocolFiles.insert(file)
    }
    DocumentedProtocolFamilies.register(families, owner: folder)
    defer { DocumentedProtocolFamilies.register([], owner: folder) }
    // A patch may apply over a Controller file of the same package, so those are read first.
    var own: [ControllerModelID: ControllerRecord] = [:]
    let listed =
      manifest.controllers.map { ($0, ControllerRecordOperation.add) }
      + manifest.patches.map { ($0, ControllerRecordOperation.patch) }
    for (file, operation) in listed {
      let url = folder.appendingPathComponent("Controllers/\(file)")
      let validated = try content(url, "Controllers/\(file)", document: "record") {
        try requireKind(of: $0, listedAs: operation)
        return try ControllerRecordSet.validate($0, file: url, layer: .package, packages: own)
      }
      if let record = validated.record, validated.operation == .add { own[record.model] = record }
      guard file == validated.fileName else {
        throw ModPackageError(
          .invalidPackageContent,
          "Controllers/\(file): the file name must be \(validated.fileName)"
        )
      }
      claims.controllerFiles.insert(file)
    }
    for file in manifest.virtualDevices {
      let url = folder.appendingPathComponent("VirtualDevices/\(file)")
      let model = try content(url, "VirtualDevices/\(file)", document: "virtualDevice") {
        try VirtualHIDProfileOverrideStore.parse($0).0
      }
      guard file == model.fileName else {
        throw ModPackageError(
          .invalidPackageContent,
          "VirtualDevices/\(file): the file name must be \(model.fileName)"
        )
      }
      claims.virtualDevices.insert(file)
    }
    for file in manifest.profiles {
      let url = folder.appendingPathComponent("Profiles/\(file)")
      let profile = try content(url, "Profiles/\(file)", document: "profile") {
        try RemappingProfileFileStore.load(from: $0)
      }
      guard claims.add(profile) else {
        throw ModPackageError(
          .packageClash,
          "Profiles/\(file) repeats the UUID or name of another profile of the package"
        )
      }
    }
    return claims
  }

  /// Refuses a Controller file listed under `patches`, and a ControllerPatch file listed under
  /// `controllers`.
  ///
  /// A file of any other kind is left to the record validation.
  private static func requireKind(
    of data: Data,
    listedAs operation: ControllerRecordOperation
  ) throws {
    let found = ((try? DocumentCoder.read(data, file: "package file")) as? [String: Any])?["kind"] as? String
    let kinds = [ControllerRecordDocument.kind, ControllerPatch.kind]
    let expected = operation == .add ? ControllerRecordDocument.kind : ControllerPatch.kind
    guard let found, found != expected, kinds.contains(found) else { return }
    let list = operation == .add ? "controllers" : "patches"
    throw ControllerRecordProblem(
      code: .invalidControllerRecord,
      key: "error.E5007.modPackage.kindMismatch",
      arguments: [list, found, expected],
      "a \(found) file is listed under \(list) in mod.plist; \(list) lists \(expected) files"
    )
  }

  /// Whether `url` is a JavaScript file. A package holds documents only, so a script is skipped
  /// like a hidden file: it is never evaluated, and an install does not copy it.
  static func isScript(_ url: URL) -> Bool {
    url.pathExtension == "js" && !isLink(url) && !isDirectory(url)
  }

  /// Refuses a link anywhere in `folder`, and an entry beside `mod.plist` that is not one of the
  /// four kind folders.
  ///
  /// Hidden entries and scripts are skipped here, and an install does not copy them.
  private static func checkLayout(of folder: URL) throws {
    guard !isLink(folder) else {
      throw ModPackageError(.invalidPackageContent, "\(folder.lastPathComponent) is a link")
    }
    let known: Set = [
      ModPackageManifest.fileName, "Controllers", "Profiles", "VirtualDevices", "Protocols",
    ]
    let entries = try? FileManager.default.contentsOfDirectory(
      at: folder,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    let unknown = (entries ?? []).filter { !isScript($0) }.map(\.lastPathComponent)
      .filter { !known.contains($0) }
    if let name = unknown.min() {
      throw ModPackageError(.invalidPackageContent, "\(name) is not part of a package")
    }
    let walk = FileManager.default.enumerator(
      at: folder,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    while let url = walk?.nextObject() as? URL {
      if isLink(url) {
        throw ModPackageError(.invalidPackageContent, "\(url.lastPathComponent) is a link")
      }
    }
  }

  /// Reads `url` and runs `check` on it, and turns each failure into E4003 naming `label`, or
  /// into E5001 when the file's `apiVersion` is not supported.
  private static func content<Value>(
    _ url: URL,
    _ label: String,
    document: String,
    _ check: (Data) throws -> Value
  ) throws -> Value {
    do { return try check(Data(contentsOf: url)) } catch {
      throw ModPackageError(
        ControllerRecordSet.problemCode(error) == .unsupportedAPIVersion
          ? .unsupportedAPIVersion : .invalidPackageContent,
        label + ": "
          + ControllerRecordSet.problemDescription(error, includingCode: false, document: document)
      )
    }
  }

  /// The claims of an installed package, from its listed files.
  ///
  /// A profile that cannot be read claims nothing.
  private static func claims(of folder: URL, _ manifest: ModPackageManifest) -> ModPackageClaims {
    var claims = ModPackageClaims()
    claims.controllerFiles = Set(manifest.controllers + manifest.patches)
    claims.virtualDevices = Set(manifest.virtualDevices)
    claims.protocolFiles = Set(manifest.protocols)
    for file in manifest.profiles {
      if let profile = try? RemappingProfileFileStore.load(
        from: folder.appendingPathComponent("Profiles/\(file)")
      ) {
        _ = claims.add(profile)
      }
    }
    return claims
  }

  /// The claims of the user's `Controllers`, `VirtualDevices`, `Profiles`, and `Protocols` folders
  /// in `root`.
  private static func userClaims(_ root: URL) -> ModPackageClaims {
    func files(_ kind: String) -> [URL] {
      let urls = try? FileManager.default.contentsOfDirectory(
        at: root.appendingPathComponent(kind),
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
      return (urls ?? []).filter { $0.pathExtension == "plist" }
    }
    var claims = ModPackageClaims()
    claims.controllerFiles = Set(files("Controllers").map(\.lastPathComponent))
    claims.protocolFiles = Set(files("Protocols").map(\.lastPathComponent))
    for url in files("VirtualDevices") {
      if let model = (try? VirtualHIDProfileOverrideStore.parse(Data(contentsOf: url)))?.0 {
        claims.virtualDevices.insert(model.fileName)
      }
    }
    for url in files("Profiles") {
      if let profile = try? RemappingProfileFileStore.load(from: url) { _ = claims.add(profile) }
    }
    return claims
  }
}
