import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
struct LibraryListingTests {
  private let userModel = ControllerModelID(vendorID: 0x1234, productID: 0x0001)
  private let builtInModel = ControllerModelID(vendorID: 0x045E, productID: 0x028E)

  private func item(
    _ model: ControllerModelID,
    _ layer: ControllerRecordLayer
  )
    -> LibraryRecordItem
  { LibraryRecordItem(model: model, family: .xboxGIP, layer: layer, file: nil) }

  private func detail(_ item: LibraryRecordItem) -> LibraryRecordDetail {
    LibraryRecordDetail(
      item: item,
      transport: "HID",
      notes: [],
      claimedByUSBExtension: nil,
      fields: [],
      record: LibraryRecordDocument(document: "<dict/>")
    )
  }

  private func loadedModel() -> (LibraryViewModel, FakeLibraryStore) {
    let store = FakeLibraryStore()
    let user = item(userModel, .user)
    let builtIn = item(builtInModel, .bundled)
    store.listing = LibraryRecordListing(installed: [user], builtIn: [builtIn])
    store.details = [userModel: detail(user), builtInModel: detail(builtIn)]
    store.mods = [
      LibraryModItem(name: "arcade", version: "1.0.0", author: "Ada", files: [], problem: nil)
    ]
    let model = LibraryViewModel(store: store) { _ in Data() }
    model.reload()
    return (model, store)
  }

  @Test
  func installedScopeListsInstalledRecordsAndMods() {
    let (model, _) = loadedModel()

    #expect(model.visibleRecords.map(\.model) == [userModel])
    #expect(model.visibleMods.map(\.name) == ["arcade"])
  }

  @Test
  func builtInScopeListsBundledRecordsAndNoMods() {
    let (model, _) = loadedModel()

    model.scope = .builtIn

    #expect(model.visibleRecords.map(\.model) == [builtInModel])
    #expect(model.visibleMods.isEmpty)
  }

  @Test
  func changingScopeClearsSelection() {
    let (model, _) = loadedModel()
    model.select(.record(userModel))

    model.scope = .builtIn

    #expect(model.selection == nil)
    #expect(model.recordDetail == nil)
  }

  @Test
  func selectingRecordShowsItsDetail() {
    let (model, _) = loadedModel()

    model.select(.record(userModel))

    #expect(model.recordDetail?.item.model == userModel)
    #expect(model.selectedMod == nil)
  }

  @Test
  func selectingModShowsMod() {
    let (model, _) = loadedModel()

    model.select(.mod("arcade"))

    #expect(model.selectedMod?.name == "arcade")
    #expect(model.recordDetail == nil)
  }

  @Test
  func selectingSomethingMissingSelectsNothing() {
    let (model, _) = loadedModel()

    model.select(.mod("missing"))

    #expect(model.selection == nil)
  }

  @Test
  func removeAndTestFollowSelection() {
    let (model, _) = loadedModel()
    #expect(!model.canRemoveSelection)
    #expect(!model.canTestSelection)

    model.select(.record(userModel))
    #expect(model.canRemoveSelection)
    #expect(model.canTestSelection)

    model.scope = .builtIn
    model.select(.record(builtInModel))
    #expect(!model.canRemoveSelection)
    #expect(model.canTestSelection)

    model.scope = .installed
    model.select(.mod("arcade"))
    #expect(model.canRemoveSelection)
    #expect(!model.canTestSelection)
  }

  @Test
  func testingRecordKeepsItsResultUntilSelectionChanges() {
    let (model, store) = loadedModel()
    store.testOutcome = ControllerRecordTestResult(
      inputReports: 2,
      differences: [.init(field: "pressed", expected: "[]", actual: "[1]")]
    )
    model.select(.record(userModel))

    model.testSelectedRecord(
      capture: URL(fileURLWithPath: "/tmp/capture.jsonl"),
      expectation: URL(fileURLWithPath: "/tmp/state.json")
    )

    #expect(store.testedRecords == [userModel])
    #expect(model.testRun?.result.matches == false)
    #expect(model.testRun?.expectation == "state.json")
    model.select(.mod("arcade"))
    #expect(model.testRun == nil)
  }

  @Test
  func testRefusalShowsFailure() {
    let (model, store) = loadedModel()
    store.refusal = LibraryFailure(message: "bad capture", code: .invalidInputFile)
    model.select(.record(userModel))

    model.testSelectedRecord(
      capture: URL(fileURLWithPath: "/tmp/capture.jsonl"),
      expectation: URL(fileURLWithPath: "/tmp/state.json")
    )

    #expect(model.testRun == nil)
    #expect(model.failure?.code == .invalidInputFile)
  }

  @Test
  func searchMatchesVendorProductFamilyNameFamilyTokenAndModNameIgnoringCase() {
    let (model, _) = loadedModel()

    model.searchText = "1234:0001"
    #expect(model.visibleRecords.map(\.model) == [userModel])
    #expect(model.visibleMods.isEmpty)
    model.searchText = PhysicalProtocolID.xboxGIP.displayName.uppercased()
    #expect(model.visibleRecords.count == 1)
    model.searchText = "XBOX-gip"
    #expect(model.visibleRecords.count == 1)
    model.searchText = "ARC"
    #expect(model.visibleRecords.isEmpty)
    #expect(model.visibleMods.map(\.name) == ["arcade"])
    model.searchText = "  "
    #expect(model.visibleRecords.count == 1)
    #expect(model.visibleMods.count == 1)
  }

  @Test
  func removingPatchClearsSelectionOfModelNoLongerInstalled() {
    let (model, store) = loadedModel()
    model.select(.record(userModel))
    store.listing = LibraryRecordListing(builtIn: store.listing.builtIn)

    model.reload()

    #expect(model.selection == nil)
    #expect(model.recordDetail == nil)
  }

  @Test
  func recordListDoesNotShowCannotBeSelected() {
    let (model, _) = loadedModel()

    model.select(.record(builtInModel))

    #expect(model.selection == nil)
  }

  @Test
  func searchThatHidesSelectionClearsIt() {
    let (model, _) = loadedModel()
    model.select(.record(userModel))

    model.searchText = "zzz"

    #expect(model.selection == nil)
    model.searchText = ""
    #expect(model.selection == nil)
  }

  @Test
  func searchThatKeepsSelectionVisibleKeepsIt() {
    let (model, _) = loadedModel()
    model.select(.record(userModel))

    model.searchText = "1234"

    #expect(model.selection == .record(userModel))
  }

  @Test
  func builtInListIsWholeBundledCatalog() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    ).appendingPathComponent("Controllers", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

    let listing = DirectoryLibraryStore(recordsDirectory: directory).records()

    #expect(listing.builtIn.count == ControllerRecordSet.bundled.records.count)
    #expect(listing.builtIn.allSatisfy { $0.patchedBy == nil })
  }

  @Test
  func searchAppliesInBuiltInScope() {
    let (model, _) = loadedModel()
    model.scope = .builtIn

    model.searchText = "028e"
    #expect(model.visibleRecords.map(\.model) == [builtInModel])
    model.searchText = "zzz"
    #expect(model.visibleRecords.isEmpty)
  }

  @Test
  func libraryToolbarEndsWithSearch() {
    #expect(MainWindowArea.library.toolbarActions(activityMode: .log).last == .searchLibrary)
  }

  @Test
  func libraryToolbarLabelsResolve() {
    for action in MainWindowArea.library.toolbarActions(activityMode: .log) {
      #expect(OJDLocalized.string(action.labelKey) != action.labelKey)
      #expect(OJDLocalized.string(action.descriptionKey) != action.descriptionKey)
      #expect(action.descriptionKey != action.labelKey)
    }
  }

  @Test
  func storeListsBundledRecordsApartFromInstalledOnes() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    ).appendingPathComponent("Controllers", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let listing = DirectoryLibraryStore(recordsDirectory: directory).records()

    #expect(listing.installed.isEmpty)
    #expect(!listing.builtIn.isEmpty)
  }
}
