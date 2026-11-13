import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

final class FakeLibraryStore: LibraryStore, @unchecked Sendable {
  var listing = LibraryRecordListing()
  var mods: [LibraryModItem] = []
  var recordCheck = LibraryRecordCheck(
    identity: "045E:028E",
    fileName: "045e-028e.plist",
    replaces: false
  )
  var modCheck = LibraryModCheck(
    name: "arcade",
    version: "1.0.0",
    author: "Ada",
    files: [],
    replaces: false
  )
  var details: [ControllerModelID: LibraryRecordDetail] = [:]
  var testOutcome = ControllerRecordTestResult(inputReports: 1, differences: [])
  var testedRecords: [ControllerModelID] = []
  var refusal: LibraryFailure?
  var recordInstalls: [Data] = []
  var modInstalls: [(URL, Bool)] = []
  var removedRecords: [ControllerModelID] = []
  var removedMods: [String] = []

  func records() -> LibraryRecordListing { listing }

  var detailReads = 0

  func recordDetail(_ model: ControllerModelID) -> LibraryRecordDetail? {
    detailReads += 1
    return details[model]
  }

  func testRecord(
    _ model: ControllerModelID,
    capture _: Data,
    captureName _: String,
    expectation _: Data,
    expectationName _: String
  ) throws -> ControllerRecordTestResult {
    if let refusal { throw refusal }
    testedRecords.append(model)
    return testOutcome
  }

  func checkRecord(_: Data) throws -> LibraryRecordCheck {
    if let refusal { throw refusal }
    return recordCheck
  }

  func installRecord(_ data: Data) throws -> LibraryRecordCheck {
    if let refusal { throw refusal }
    recordInstalls.append(data)
    return recordCheck
  }

  func removeRecord(_ model: ControllerModelID) throws {
    if let refusal { throw refusal }
    removedRecords.append(model)
  }

  func installedMods() -> [LibraryModItem] { mods }

  func checkMod(folder _: URL) throws -> LibraryModCheck {
    if let refusal { throw refusal }
    return modCheck
  }

  func installMod(folder: URL, replace: Bool) throws {
    if let refusal { throw refusal }
    modInstalls.append((folder, replace))
  }

  func removeMod(name: String) throws {
    if let refusal { throw refusal }
    removedMods.append(name)
  }
}

@MainActor
struct LibraryViewModelTests {
  private let file = URL(fileURLWithPath: "/tmp/045e-028e.plist")

  private func temporaryFile() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    FileManager.default.createFile(atPath: url.path, contents: Data("{}".utf8))
    return url
  }

  private func temporaryFolder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func makeModel(
    _ store: FakeLibraryStore,
    read: @escaping (URL) throws -> Data = { _ in Data("{}".utf8) }
  ) -> LibraryViewModel { LibraryViewModel(store: store, readFile: read) }

  @Test
  func installingARecordWaitsForConfirmation() {
    let store = FakeLibraryStore()
    let model = makeModel(store)

    model.beginInstallRecord(from: file)

    #expect(store.recordInstalls.isEmpty)
    guard case .installRecord(_, let check) = model.pending else {
      Issue.record("Expected a pending record install")
      return
    }
    #expect(check.identity == "045E:028E")
    #expect(model.pending?.confirmation.isDestructive == false)
  }

  @Test
  func replacingARecordAsksForAReplaceSheet() {
    let store = FakeLibraryStore()
    store.recordCheck = LibraryRecordCheck(
      identity: "045E:028E",
      fileName: "045e-028e.patch.plist",
      replaces: true
    )
    let model = makeModel(store)

    model.beginInstallRecord(from: file)

    #expect(model.pending?.confirmation.isDestructive == true)
    #expect(model.pending?.confirmation.confirmTitle == OJDLocalized.string("ui.library.replace"))
  }

  @Test
  func confirmingInstallsWritesTheReadBytesAndReloads() {
    let store = FakeLibraryStore()
    let bytes = Data("record".utf8)
    let model = makeModel(store) { _ in bytes }
    model.beginInstallRecord(from: file)
    store.mods = [
      LibraryModItem(name: "arcade", version: nil, author: nil, files: [], problem: nil)
    ]

    let changed = model.confirmPending()

    #expect(changed)
    #expect(store.recordInstalls == [bytes])
    #expect(model.pending == nil)
    #expect(model.mods.map(\.name) == ["arcade"])
    #expect(model.failure == nil)
  }

  @Test
  func cancellingChangesNothing() {
    let store = FakeLibraryStore()
    let model = makeModel(store)
    model.beginInstallMod(from: file)

    model.cancelPending()

    #expect(model.pending == nil)
    #expect(store.modInstalls.isEmpty)
  }

  @Test
  func aReplacedModIsInstalledWithReplace() {
    let store = FakeLibraryStore()
    store.modCheck = LibraryModCheck(
      name: "arcade",
      version: "2.0.0",
      author: "Ada",
      files: [],
      replaces: true
    )
    let model = makeModel(store)
    model.beginInstallMod(from: file)

    model.confirmPending()

    #expect(store.modInstalls.map(\.1) == [true])
  }

  @Test
  func aRefusalShowsTheCodeAndOpensNoSheet() {
    let store = FakeLibraryStore()
    store.refusal = LibraryFailure(message: "refused", code: .invalidInputFile)
    let model = makeModel(store)

    model.beginInstallRecord(from: file)

    #expect(model.pending == nil)
    #expect(model.failure?.code == .invalidInputFile)
  }

  @Test
  func anUnreadableFileIsAFileAccessFailure() {
    struct Unreadable: Error {}
    let model = makeModel(FakeLibraryStore()) { _ in throw Unreadable() }

    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }

    model.validate(at: url)

    #expect(model.failure?.code == .fileAccessFailed)
    #expect(model.notice == nil)
  }

  @Test
  func validatingReportsWithoutInstalling() {
    let store = FakeLibraryStore()
    let model = makeModel(store)

    let url = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: url) }

    model.validate(at: url)

    #expect(model.notice != nil)
    #expect(model.pending == nil)
    #expect(store.modInstalls.isEmpty)
  }

  @Test
  func removingARecordNeedsConfirmationThenRemovesItsModel() {
    let store = FakeLibraryStore()
    let item = LibraryRecordItem(
      model: ControllerModelID(vendorID: 0x045E, productID: 0x028E),
      family: .xboxGIP,
      layer: .user,
      file: nil
    )
    store.listing = LibraryRecordListing(installed: [item])
    store.details[item.model] = LibraryRecordDetail(
      item: item,
      transport: "HID",
      notes: [],
      claimedByUSBExtension: nil,
      fields: [],
      record: LibraryRecordDocument(document: "<dict/>\n")
    )
    let model = makeModel(store)
    model.reload()
    model.select(.record(item.model))
    model.select(.record(item.model))
    #expect(store.detailReads == 1)

    model.requestRemoveSelection()
    #expect(store.removedRecords.isEmpty)
    #expect(model.pending?.confirmation.isDestructive == true)
    model.confirmPending()

    #expect(store.removedRecords == [item.model])
  }

  @Test
  func onlyUserRecordsAreRemovable() {
    let model = ControllerModelID(vendorID: 1, productID: 2)
    func item(_ layer: ControllerRecordLayer) -> LibraryRecordItem {
      LibraryRecordItem(model: model, family: .xboxGIP, layer: layer, file: nil)
    }
    #expect(item(.user).isRemovable)
    #expect(!item(.package).isRemovable)
  }

  @Test
  func removingAModRemovesItByName() {
    let store = FakeLibraryStore()
    store.mods = [
      LibraryModItem(name: "arcade", version: nil, author: nil, files: [], problem: nil)
    ]
    let model = makeModel(store)
    model.reload()
    model.select(.mod("arcade"))

    model.requestRemoveSelection()
    model.confirmPending()

    #expect(store.removedMods == ["arcade"])
  }
}

struct DirectoryLibraryStoreTests {
  private func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    ).appendingPathComponent("Controllers", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test
  func anInvalidRecordIsRefusedWithAnInputFileCode() throws {
    let store = DirectoryLibraryStore(recordsDirectory: try directory())

    do {
      _ = try store.checkRecord(Data("{}".utf8))
      Issue.record("Expected the record to be refused")
    } catch let failure as LibraryFailure {
      #expect(failure.code != nil)
    }
  }

  @Test
  func removingAMissingRecordIsNotFound() throws {
    let store = DirectoryLibraryStore(recordsDirectory: try directory())

    do {
      try store.removeRecord(ControllerModelID(vendorID: 1, productID: 2))
      Issue.record("Expected a missing record")
    } catch let failure as LibraryFailure {
      #expect(failure.code == .notFound)
    }
  }

  @Test
  func anEmptyStoreListsNothing() throws {
    let store = DirectoryLibraryStore(recordsDirectory: try directory())

    #expect(store.records().installed.isEmpty)
    #expect(store.installedMods().isEmpty)
  }

  @Test
  func aSkippedFileCarriesItsReason() throws {
    let directory = try directory()
    try PropertyListFixture.data(json: "{}").write(
      to: directory.appendingPathComponent("bad.plist")
    )
    let store = DirectoryLibraryStore(recordsDirectory: directory)

    let skipped = store.records().skipped

    #expect(skipped.count == 1)
    #expect(skipped.allSatisfy { !$0.problem.isEmpty })
  }
}
