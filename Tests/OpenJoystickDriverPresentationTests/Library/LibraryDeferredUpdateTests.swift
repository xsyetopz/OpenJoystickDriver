import Testing

@testable import OpenJoystickDriverPresentation

/// The list's own callbacks (appearing, selecting a row) run inside NSTableView's delegate, so
/// the model they change must not publish before they return.
@MainActor
struct LibraryDeferredUpdateTests {
  private func makeModel(_ store: FakeLibraryStore) -> LibraryViewModel {
    store.mods = [
      LibraryModItem(name: "arcade", version: "1.0.0", author: "Ada", files: [], problem: nil)
    ]
    return LibraryViewModel(store: store)
  }

  private func drainMainActor() async {
    for _ in 0..<5 { await Task.yield() }
  }

  @Test
  func reloadAfterRenderPublishesOnlyAfterCallbackReturns() async {
    let store = FakeLibraryStore()
    let model = makeModel(store)

    model.reloadAfterRender()

    #expect(model.mods.isEmpty)
    await drainMainActor()
    #expect(model.mods.map(\.name) == ["arcade"])
  }

  @Test
  func selectAfterRenderPublishesOnlyAfterCallbackReturns() async {
    let store = FakeLibraryStore()
    let model = makeModel(store)
    model.reload()

    model.selectAfterRender(.mod("arcade"))

    #expect(model.selection == nil)
    await drainMainActor()
    #expect(model.selection == .mod("arcade"))
  }
}
