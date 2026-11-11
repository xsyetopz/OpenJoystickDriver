import Foundation

extension DocumentedProtocolFamilies {
  /// `~/Library/Application Support/OpenJoystickDriver/Protocols`.
  public static var userDirectory: URL { directory(besides: ControllerRecordSet.userDirectory) }

  /// The `Protocols` folder beside a user `Controllers` directory, such as the one a test passes.
  public static func directory(besides controllers: URL) -> URL {
    controllers.deletingLastPathComponent().appendingPathComponent("Protocols", isDirectory: true)
  }

  /// Reads and checks the description file `file` as a documented family.
  ///
  /// - Throws: ``ProtocolDescriptionProblem``: E5002 for a document that is invalid, that names a
  ///   built-in family, or that sets no display name or no input layouts, and E5003 for a file
  ///   name that is not the family's.
  public static func read(
    _ file: URL,
    package: String? = nil
  ) throws(ProtocolDescriptionProblem) -> DocumentedProtocolFamily {
    let data: Data
    do { data = try Data(contentsOf: file) } catch {
      throw ProtocolDescriptionProblem(
        .invalidProtocolDescription,
        "\(file.lastPathComponent): \(error.localizedDescription)"
      )
    }
    let description = try ProtocolDescription.decode(data, fileName: file.lastPathComponent)
    guard let displayName = description.displayName else {
      throw ProtocolDescriptionProblem(
        .invalidProtocolDescription,
        "\(file.lastPathComponent): \(description.family.rawValue) is a built-in family; a "
          + "documented family needs a name of its own"
      )
    }
    return DocumentedProtocolFamily(
      name: description.family.rawValue,
      displayName: displayName,
      file: file,
      package: package,
      description: description
    )
  }

  /// Registers the families of the user's `Protocols` folder beside `controllers`, then those of the
  /// installed packages in name order, and returns the families and the files that were refused.
  ///
  /// The first definition of a name wins, so a later file with the same name is refused. A package
  /// that cannot be used holds nothing.
  public static func load(
    besides controllers: URL
  ) -> (families: [DocumentedProtocolFamily], refused: [ControllerRecordFile]) {
    let folder = directory(besides: controllers)
    var sources: [(file: URL, package: String?)] = fileURLs(in: folder).map { ($0, nil) }
    let store = ModPackageStore(directory: ModPackageStore.directory(besides: controllers))
    for package in store.list() where package.problem == nil {
      sources += (package.manifest?.protocols ?? []).sorted().map {
        (package.directory.appendingPathComponent("Protocols/\($0)"), package.name)
      }
    }
    var families: [DocumentedProtocolFamily] = []
    var refused: [ControllerRecordFile] = []
    for source in sources {
      do {
        let family = try read(source.file, package: source.package)
        if let held = families.first(where: { $0.name == family.name }) {
          throw ProtocolDescriptionProblem(
            .invalidProtocolDescription,
            "\(source.file.lastPathComponent): \(family.name) is already defined by "
              + (held.package.map { "package \($0)" } ?? "your Protocols folder")
          )
        }
        families.append(family)
      } catch {
        refused.append(
          ControllerRecordFile(url: source.file, model: nil, operation: nil, problem: "\(error)")
        )
      }
    }
    register(families, owner: controllers.deletingLastPathComponent())
    return (families, refused)
  }

  /// The `.plist` files of `folder` in file-name order.
  static func fileURLs(in folder: URL) -> [URL] {
    let urls = try? FileManager.default.contentsOfDirectory(
      at: folder,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    return (urls ?? []).filter { $0.pathExtension == "plist" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }
}
