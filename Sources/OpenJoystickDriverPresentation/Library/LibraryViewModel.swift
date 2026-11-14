import Combine
import Foundation
import OpenJoystickDriverKit

/// An operation that waits for the person's confirmation in a window-modal sheet.
enum LibraryPending: Identifiable, Equatable {
  /// Installing a record file, with its data and what validation found.
  case installRecord(data: Data, check: LibraryRecordCheck)
  /// Installing a mod folder, with what validation found.
  case installMod(folder: URL, check: LibraryModCheck)
  /// Removing a record file.
  case removeRecord(LibraryRecordItem)
  /// Removing a mod package.
  case removeMod(LibraryModItem)

  /// The kind of the change with the file name, name or identity of its item.
  var id: String {
    switch self {
    case .installRecord(_, let check): "installRecord.\(check.fileName)"
    case .installMod(_, let check): "installMod.\(check.name)"
    case .removeRecord(let item): "removeRecord.\(item.identity)"
    case .removeMod(let item): "removeMod.\(item.name)"
    }
  }
}

/// The text and button of a confirmation sheet; its wording matches the action.
struct LibraryConfirmation: Equatable {
  /// The question the sheet asks.
  let title: String
  /// The explanation under the question.
  let message: String
  /// The title of the confirming button.
  let confirmTitle: String
  /// Whether the operation replaces or removes something.
  let isDestructive: Bool
}

extension LibraryPending {
  /// The sheet text for the operation: Install or Replace for an install that finds a file of the
  /// same name, and Remove for a removal.
  var confirmation: LibraryConfirmation {
    switch self {
    case .installRecord(_, let check):
      return LibraryConfirmation(
        title: check.replaces
          ? OJDLocalized.formatted("ui.library.record.replace.title", check.identity)
          : OJDLocalized.formatted("ui.library.record.install.title", check.identity),
        message: check.replaces
          ? OJDLocalized.formatted("ui.library.record.replace.message", check.fileName)
          : OJDLocalized.formatted("ui.library.record.install.message", check.fileName),
        confirmTitle: check.replaces
          ? OJDLocalized.string("ui.library.replace") : OJDLocalized.string("ui.library.install"),
        isDestructive: check.replaces
      )
    case .installMod(_, let check):
      return LibraryConfirmation(
        title: check.replaces
          ? OJDLocalized.formatted("ui.library.mod.replace.title", check.name)
          : OJDLocalized.formatted("ui.library.mod.install.title", check.name),
        message: check.replaces
          ? OJDLocalized.formatted("ui.library.mod.replace.message", check.name, check.version)
          : OJDLocalized.formatted(
            "ui.library.mod.install.message",
            check.name,
            check.version,
            check.author
          ),
        confirmTitle: check.replaces
          ? OJDLocalized.string("ui.library.replace") : OJDLocalized.string("ui.library.install"),
        isDestructive: check.replaces
      )
    case .removeRecord(let item):
      return LibraryConfirmation(
        title: OJDLocalized.formatted("ui.library.record.remove.title", item.identity),
        message: OJDLocalized.string("ui.library.record.remove.message"),
        confirmTitle: OJDLocalized.string("ui.library.remove"),
        isDestructive: true
      )
    case .removeMod(let item):
      return LibraryConfirmation(
        title: OJDLocalized.formatted("ui.library.mod.remove.title", item.name),
        message: OJDLocalized.string("ui.library.mod.remove.message"),
        confirmTitle: OJDLocalized.string("ui.library.remove"),
        isDestructive: true
      )
    }
  }
}

/// Which records the Library list shows: those a file or a mod adds, or those the app comes with.
enum LibraryScope: String, CaseIterable, Identifiable {
  /// Records and mods that a file or a package adds.
  case installed
  /// The records that the app comes with.
  case builtIn

  /// The raw value, which identifies the scope.
  var id: String { rawValue }
  /// The localization key of the scope's title in the switch.
  var titleKey: String {
    switch self {
    case .installed: return "ui.library.installed"
    case .builtIn: return "ui.library.builtIn"
    }
  }
}

/// The record or mod the detail column shows.
enum LibrarySelection: Hashable {
  /// A record, by its vendor and product ID.
  case record(ControllerModelID)
  /// A mod, by its name.
  case mod(String)
}

/// The state of the Library area: the scope, the search text, the selection and the operation
/// that waits for confirmation.
@MainActor
final class LibraryViewModel: ObservableObject {
  /// Which records the list shows; a change of scope clears the selection.
  @Published
  var scope: LibraryScope = .installed {
    didSet { if scope != oldValue { select(nil) } }
  }
  /// What the toolbar's search field holds; the list shows only records and mods that match.
  @Published
  var searchText = "" {
    didSet { if searchText != oldValue { select(selection) } }
  }
  /// The selected record or mod, or nil.
  @Published
  private(set) var selection: LibrarySelection?
  /// The records of both scopes and the skipped files.
  @Published
  private(set) var records = LibraryRecordListing()
  /// The installed mods.
  @Published
  private(set) var mods: [LibraryModItem] = []
  /// The full record of the selected record, or nil.
  @Published
  private(set) var recordDetail: LibraryRecordDetail?
  /// The latest test of the selected record, or nil.
  @Published
  private(set) var testRun: LibraryTestRun?
  /// The failure of the latest operation, or nil.
  @Published
  private(set) var failure: LibraryFailure?
  /// The result of the latest successful operation, in words, or nil.
  @Published
  private(set) var notice: String?
  /// The operation that waits for the person's confirmation, or nil.
  @Published
  var pending: LibraryPending?

  /// The store that reads and changes the records and packages.
  private let store: any LibraryStore
  /// Reads a file the person chose.
  private let readFile: (URL) throws -> Data

  /// Creates the model on a store and a file reader.
  ///
  /// - Parameters:
  ///   - store: The store; the default works on the user's record folder.
  ///   - readFile: Reads the data of a file; the default reads from disk.
  init(
    store: any LibraryStore = DirectoryLibraryStore(),
    readFile: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) }
  ) {
    self.store = store
    self.readFile = readFile
  }

  /// The records the list shows under ``scope``, filtered by ``searchText``.
  var visibleRecords: [LibraryRecordItem] {
    (scope == .installed ? records.installed : records.builtIn).filter {
      $0.matches(searchText)
    }
  }

  /// The mods the list shows under ``scope``; built-in records come with no mods.
  var visibleMods: [LibraryModItem] {
    scope == .installed ? mods.filter { $0.matches(searchText) } : []
  }

  /// The selected mod, or nil when a record or nothing is selected.
  var selectedMod: LibraryModItem? {
    guard case .mod(let name) = selection else { return nil }
    return mods.first { $0.name == name }
  }

  /// Whether Remove applies: a user's record file, or a mod.
  var canRemoveSelection: Bool {
    if selectedMod != nil { return true }
    return recordDetail?.item.isRemovable == true
  }

  /// Whether a record is selected, so that Test applies.
  var canTestSelection: Bool { recordDetail != nil }

  /// Reads the records and mods from the store and keeps the selection when the list still
  /// shows it.
  func reload() {
    records = store.records()
    mods = store.installedMods()
    recordDetail = nil
    select(selection)
  }

  /// Runs ``reload()`` after the current view update.
  ///
  /// The list calls this while it appears, inside NSTableView's delegate, where publishing a
  /// change to the list's own rows is a reentrant operation.
  func reloadAfterRender() {
    Task { @MainActor in reload() }
  }

  /// Runs ``select(_:)`` after the list's selection callback returns, for the same reason as
  /// ``reloadAfterRender()``.
  func selectAfterRender(_ selection: LibrarySelection?) {
    Task { @MainActor in select(selection) }
  }

  /// Shows `selection`; a record or mod that the list does not show selects nothing.
  ///
  /// The record is read from the store once: selecting the record that is already shown, as the
  /// list's binding and a change of the search text do, keeps the detail read before.
  func select(_ selection: LibrarySelection?) {
    switch selection {
    case .record(let model)?:
      if recordDetail?.item.model != model {
        recordDetail =
          visibleRecords.contains { $0.model == model } ? store.recordDetail(model) : nil
      } else if !visibleRecords.contains(where: { $0.model == model }) {
        recordDetail = nil
      }
      self.selection = recordDetail == nil ? nil : selection
    case .mod(let name)?:
      recordDetail = nil
      self.selection = visibleMods.contains { $0.name == name } ? selection : nil
    case nil:
      recordDetail = nil
      self.selection = nil
    }
    if testRun?.model != recordDetail?.item.model { testRun = nil }
  }

  /// Converts the stale documents of the support folder, then reloads; a document that cannot be
  /// converted shows as the failure.
  func migrate(_ migrator: DocumentMigrator = DocumentMigrator()) {
    failure =
      migrator.run(dryRun: false).contains { $0.verdict == .failed }
      ? LibraryFailure(
        message: OJDLocalized.string("platform.macos.ui.migrate.failed"),
        code: .unsupportedAPIVersion
      ) : nil
    reload()
  }

  /// Clears the failure.
  func dismissFailure() { failure = nil }

  /// Clears the notice.
  func dismissNotice() { notice = nil }

  /// Checks the record file or mod folder at `url` without installing it; a folder is a mod.
  ///
  /// The result shows as the notice or the failure.
  func validate(at url: URL) {
    perform {
      if try isFolder(url) {
        let check = try store.checkMod(folder: url)
        notice = OJDLocalized.formatted("ui.library.mod.valid", url.lastPathComponent, check.name)
      } else {
        let check = try store.checkRecord(try read(url))
        notice = OJDLocalized.formatted(
          "ui.library.record.valid",
          url.lastPathComponent,
          check.identity
        )
      }
    }
  }

  /// Starts installing the record file at `url`: it validates the file and waits for the
  /// person's confirmation in ``pending``.
  func beginInstallRecord(from url: URL) {
    perform {
      let data = try read(url)
      pending = .installRecord(data: data, check: try store.checkRecord(data))
    }
  }

  /// Starts installing the record file or mod folder at `url`; a folder is a mod.
  func beginInstall(from url: URL) {
    perform {
      if try isFolder(url) { beginInstallMod(from: url) } else { beginInstallRecord(from: url) }
    }
  }

  /// Returns whether `url` is a folder.
  ///
  /// - Throws: ``LibraryFailure`` when the file system cannot say.
  private func isFolder(_ url: URL) throws -> Bool {
    do { return try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true } catch {
      throw LibraryFailure(
        message: OJDLocalized.formatted(
          "ui.library.unreadable",
          url.path,
          error.localizedDescription
        ),
        code: .fileAccessFailed
      )
    }
  }

  /// Starts installing the mod in `folder`: it validates the package and waits for the person's
  /// confirmation in ``pending``.
  func beginInstallMod(from folder: URL) {
    perform { pending = .installMod(folder: folder, check: try store.checkMod(folder: folder)) }
  }

  /// Asks to remove the selected mod or record file.
  func requestRemoveSelection() {
    if let mod = selectedMod {
      pending = .removeMod(mod)
    } else if let item = recordDetail?.item, item.isRemovable {
      pending = .removeRecord(item)
    }
  }

  /// Replays the capture at `capture` through the selected record's parser and compares the state
  /// with the one at `expectation`.
  ///
  /// The result shows in ``testRun`` or ``failure``.
  func testSelectedRecord(capture: URL, expectation: URL) {
    guard let model = recordDetail?.item.model else { return }
    perform {
      testRun = nil
      let result = try store.testRecord(
        model,
        capture: try read(capture),
        captureName: capture.lastPathComponent,
        expectation: try read(expectation),
        expectationName: expectation.lastPathComponent
      )
      testRun = LibraryTestRun(
        model: model,
        expectation: expectation.lastPathComponent,
        result: result
      )
    }
  }

  /// Drops the operation that waits for confirmation.
  func cancelPending() { pending = nil }

  /// Runs the confirmed operation, reloads the Library and shows the result as the notice.
  ///
  /// Returns whether it changed the library.
  @discardableResult
  func confirmPending() -> Bool {
    guard let operation = pending else { return false }
    pending = nil
    return perform {
      switch operation {
      case .installRecord(let data, _):
        let check = try store.installRecord(data)
        notice = OJDLocalized.formatted("ui.library.record.installed", check.identity)
      case .installMod(let folder, let check):
        try store.installMod(folder: folder, replace: check.replaces)
        notice = OJDLocalized.formatted("ui.library.mod.installed", check.name)
      case .removeRecord(let item):
        try store.removeRecord(item.model)
        notice = OJDLocalized.formatted("ui.library.record.removed", item.identity)
      case .removeMod(let item):
        try store.removeMod(name: item.name)
        notice = OJDLocalized.formatted("ui.library.mod.removed", item.name)
      }
      reload()
    }
  }

  /// Reads the file at `url` through ``readFile``.
  ///
  /// - Throws: ``LibraryFailure`` with the file access error code when the file cannot be read.
  private func read(_ url: URL) throws -> Data {
    do { return try readFile(url) } catch {
      throw LibraryFailure(
        message: OJDLocalized.formatted(
          "ui.library.unreadable",
          url.path,
          error.localizedDescription
        ),
        code: .fileAccessFailed
      )
    }
  }

  /// Runs `body` after clearing the failure and the notice.
  ///
  /// A thrown error becomes ``failure``. Returns whether `body` finished without an error.
  @discardableResult
  private func perform(_ body: () throws -> Void) -> Bool {
    failure = nil
    notice = nil
    do {
      try body()
      return true
    } catch let error as LibraryFailure {
      failure = error
    } catch {
      failure = LibraryFailure(message: error.localizedDescription, code: nil)
    }
    return false
  }
}
