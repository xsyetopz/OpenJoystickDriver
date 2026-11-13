import AppKit
import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct MainWindowNavigationTests {
  @Test
  @MainActor
  func dockIconShowsWhileShowInDockIsOnOrWindowIsOpen() {
    var requestedPolicies: [NSApplication.ActivationPolicy] = []
    let dock = DockIconController(
      setActivationPolicy: { policy in
        requestedPolicies.append(policy)
        return true
      },
      activation: FakeActivation().activation
    )

    // Show in Dock off, no window: no icon.
    #expect(dock.appliedPolicy == .accessory)
    // Show in Dock off, a window open: icon until the last window closes.
    dock.setOpen(.workbench, true)
    dock.setOpen(.inputTest, true)
    dock.setOpen(.workbench, false)
    #expect(dock.appliedPolicy == .regular)
    dock.setOpen(.inputTest, false)
    #expect(dock.appliedPolicy == .accessory)
    #expect(requestedPolicies == [.regular, .accessory])

    // Show in Dock on: icon with or without a window.
    dock.showsAlways = true
    #expect(dock.appliedPolicy == .regular)
    dock.setOpen(.settings, true)
    dock.setOpen(.settings, false)
    #expect(dock.appliedPolicy == .regular)
    dock.showsAlways = false
    #expect(dock.appliedPolicy == .accessory)
  }

  @Test(arguments: [DockIconController.Window.workbench, .settings, .inputTest])
  @MainActor
  func activeAppThatTurnsRegularHandsActivationToDockAndTakesItBack(
    _ window: DockIconController.Window
  ) {
    let fake = FakeActivation()
    fake.isActive = true
    let dock = DockIconController(setActivationPolicy: { _ in true }, activation: fake.activation)

    dock.setOpen(window, true)
    #expect(fake.events == ["observe", "activate Dock"])
    #expect(dock.isHandingOffActivation)

    fake.resignActive()
    #expect(fake.events == ["observe", "activate Dock", "stop", "activate app"])
    #expect(!dock.isHandingOffActivation)
    // The observation ended: a later resign leaves the app inactive.
    fake.resignActive()
    #expect(fake.events.filter { $0 == "activate app" }.count == 1)

    // Another window opens while the app is regular: no switch, no hand-off.
    dock.setOpen(window == .settings ? .workbench : .settings, true)
    #expect(fake.events.count == 4)
  }

  @Test
  @MainActor
  func showInDockTurningOnWhileAppIsActiveHandsActivationToDock() {
    let fake = FakeActivation()
    fake.isActive = true
    let dock = DockIconController(setActivationPolicy: { _ in true }, activation: fake.activation)

    dock.showsAlways = true
    #expect(fake.events == ["observe", "activate Dock"])
  }

  @Test
  @MainActor
  func inactiveAppThatTurnsRegularHandsNothingOff() {
    let fake = FakeActivation()
    let dock = DockIconController(setActivationPolicy: { _ in true }, activation: fake.activation)

    dock.setOpen(.workbench, true)
    #expect(fake.events.isEmpty)
    #expect(!dock.isHandingOffActivation)
  }

  @Test
  @MainActor
  func turningAccessoryBeforeResignEndsHandOff() {
    let fake = FakeActivation()
    fake.isActive = true
    let dock = DockIconController(setActivationPolicy: { _ in true }, activation: fake.activation)

    dock.setOpen(.workbench, true)
    dock.setOpen(.workbench, false)
    #expect(!dock.isHandingOffActivation)
    fake.resignActive()
    #expect(fake.events == ["observe", "activate Dock", "stop"])

    // The next switch to regular of the active app hands off once more.
    fake.isActive = true
    dock.setOpen(.workbench, true)
    #expect(fake.events == ["observe", "activate Dock", "stop", "observe", "activate Dock"])
  }

  @Test(arguments: [DockIconController.DockActivation.notRunning, .refused])
  @MainActor
  func dockThatDoesNotActivateEndsHandOff(_ outcome: DockIconController.DockActivation) {
    let fake = FakeActivation()
    fake.isActive = true
    fake.dockActivation = outcome
    let dock = DockIconController(setActivationPolicy: { _ in true }, activation: fake.activation)

    dock.setOpen(.workbench, true)
    #expect(!dock.isHandingOffActivation)
    fake.resignActive()
    #expect(fake.events == ["observe", "activate Dock", "stop"])
  }

  @Test
  @MainActor
  func refusedPolicyChangeIsRetriedOnNextChange() {
    var shouldSucceed = false
    var requestedPolicies: [NSApplication.ActivationPolicy] = []
    let fake = FakeActivation()
    fake.isActive = true
    let dock = DockIconController(
      setActivationPolicy: { policy in
        requestedPolicies.append(policy)
        return shouldSucceed
      },
      activation: fake.activation
    )

    dock.setOpen(.settings, true)
    #expect(dock.appliedPolicy == .accessory)
    #expect(fake.events.isEmpty)
    shouldSucceed = true
    dock.setOpen(.workbench, true)
    #expect(dock.appliedPolicy == .regular)
    #expect(requestedPolicies == [.regular, .regular])
    #expect(fake.events == ["observe", "activate Dock"])
  }

  @Test
  @MainActor
  func menuProfileMutationIsRefusedWhileEditorHoldsOneAndRunsOnceReleased() async {
    let navigation = MainWindowNavigationModel(
      persistence: UserDefaultsMainWindowAreaPersistence(
        defaults: UserDefaults(suiteName: "MainWindowNavigationTests.\(UUID().uuidString)")!
      )
    )
    let editorRequest = RuntimeMutationRequest(operation: .create(profileID: UUID()))
    #expect(navigation.beginProfilesEditorMutation(editorRequest))

    var runs = 0
    let menuRequest = RuntimeMutationRequest(operation: .activate(profileID: UUID()))
    let refused: Int? = await navigation.trackMenuProfileMutation(menuRequest) {
      runs += 1
      return runs
    }
    #expect(refused == nil)
    #expect(runs == 0)

    navigation.finishProfilesEditorMutation(editorRequest)
    let ran: Int? = await navigation.trackMenuProfileMutation(menuRequest) {
      runs += 1
      return runs
    }
    #expect(ran == 1)
    #expect(!navigation.ownsProfilesEditorMutation(menuRequest))
  }

  @MainActor
  private static func dirtyNavigation() -> MainWindowNavigationModel {
    let navigation = MainWindowNavigationModel(
      persistence: UserDefaultsMainWindowAreaPersistence(
        defaults: UserDefaults(suiteName: "MainWindowNavigationTests.\(UUID().uuidString)")!
      )
    )
    navigation.requestArea(.profiles)
    navigation.setProfilesEditorDirty(true)
    return navigation
  }

  @Test
  @MainActor
  func actionWaitsForDiscardAnswerAndRunsAfterDiscard() {
    let navigation = Self.dirtyNavigation()
    var runs = 0
    #expect(!navigation.perform(in: .library) { runs += 1 })
    #expect(runs == 0)
    #expect(navigation.isDiscardConfirmationPresented)
    navigation.discardPendingArea()
    #expect(navigation.selectedArea == .library)
    #expect(runs == 1)
  }

  @Test
  @MainActor
  func actionIsDroppedWhenDiscardIsCancelled() {
    let navigation = Self.dirtyNavigation()
    var runs = 0
    navigation.perform(in: .library) { runs += 1 }
    navigation.cancelPendingArea()
    navigation.requestArea(.library)
    navigation.cancelPendingArea()
    navigation.discardPendingArea()
    #expect(runs == 0)
  }

  @Test
  @MainActor
  func actionRunsAtOnceInSelectedAreaAndIsRefusedDuringMutation() {
    let navigation = Self.dirtyNavigation()
    var runs = 0
    #expect(navigation.perform(in: .profiles) { runs += 1 })
    #expect(runs == 1)
    let request = RuntimeMutationRequest(operation: .create(profileID: UUID()))
    #expect(navigation.beginProfilesEditorMutation(request))
    #expect(!navigation.perform(in: .profiles) { runs += 1 })
    #expect(runs == 1)
    #expect(navigation.isMutationRefusalPresented)
  }

  @Test
  func mainWindowUsesStableContentSizingAcrossAreas() {
    #expect(MainWindowSizingPolicy.defaultContentSize == NSSize(width: 1_040, height: 700))
    #expect(MainWindowSizingPolicy.minimumContentHeight == 560)
  }

  @Test
  func restoredAndLiveResizeFramesCannotCrossContentMinimum() {
    let minimum = NSSize(width: 816, height: 604)
    let restored = WindowFramePolicy.fittingFrame(
      NSRect(x: 200, y: 300, width: 640, height: 420),
      minimumSize: minimum
    )
    #expect(restored == NSRect(x: 200, y: 116, width: 816, height: 604))
    #expect(
      WindowFramePolicy.fittingSize(NSSize(width: 700, height: 500), minimumSize: minimum)
        == minimum
    )
    #expect(
      WindowFramePolicy.fittingSize(NSSize(width: 1_100, height: 760), minimumSize: minimum)
        == NSSize(width: 1_100, height: 760)
    )
  }

  @Test
  func restoredWindowFramesAreClampedToUsableScreen() {
    let screen = NSRect(x: 0, y: 0, width: 1_440, height: 900)
    #expect(
      WindowFramePolicy.clampedFrame(NSRect(x: 1_300, y: -100, width: 900, height: 620), to: screen)
        == NSRect(x: 540, y: 0, width: 900, height: 620)
    )
    #expect(
      WindowFramePolicy.clampedFrame(
        NSRect(x: 1_300, y: 700, width: 500, height: 300),
        to: screen,
        minimumSize: NSSize(width: 816, height: 604)
      ) == NSRect(x: 624, y: 296, width: 816, height: 604)
    )
  }

  @Test
  @MainActor
  func restoresLastAcceptedArea() {
    let suiteName = "MainWindowNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let persistence = UserDefaultsMainWindowAreaPersistence(defaults: defaults)

    let initial = MainWindowNavigationModel(persistence: persistence)
    #expect(initial.selectedArea == .controllers)
    initial.requestArea(.profiles)
    #expect(initial.selectedArea == .profiles)

    let restored = MainWindowNavigationModel(persistence: persistence)
    #expect(restored.selectedArea == .profiles)
  }

  @Test
  @MainActor
  func dirtySelectionPersistsOnlyAfterDiscard() {
    let suiteName = "MainWindowNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let persistence = UserDefaultsMainWindowAreaPersistence(defaults: defaults)

    let navigation = MainWindowNavigationModel(persistence: persistence)
    navigation.requestArea(.controllers)
    navigation.setProfilesEditorDirty(true)
    navigation.requestArea(.library)

    #expect(navigation.selectedArea == .controllers)
    #expect(navigation.pendingArea == .library)
    #expect(navigation.isDiscardConfirmationPresented)
    let beforeDiscard = MainWindowNavigationModel(persistence: persistence)
    #expect(beforeDiscard.selectedArea == .controllers)

    navigation.discardPendingArea()
    #expect(navigation.selectedArea == .library)
    #expect(navigation.pendingArea == nil)
    #expect(!navigation.isDiscardConfirmationPresented)
    let afterDiscard = MainWindowNavigationModel(persistence: persistence)
    #expect(afterDiscard.selectedArea == .library)
  }

  @Test
  @MainActor
  func canceledDirtySelectionLeavesPersistedAreaUnchanged() {
    let suiteName = "MainWindowNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let persistence = UserDefaultsMainWindowAreaPersistence(defaults: defaults)

    let navigation = MainWindowNavigationModel(persistence: persistence)
    navigation.requestArea(.controllers)
    navigation.setProfilesEditorDirty(true)
    navigation.requestArea(.activity)
    navigation.cancelPendingArea()

    #expect(navigation.selectedArea == .controllers)
    #expect(navigation.pendingArea == nil)
    let restored = MainWindowNavigationModel(persistence: persistence)
    #expect(restored.selectedArea == .controllers)
  }

  @Test
  @MainActor
  func activeProfileMutationKeepsProfilesAreaMountedUntilResolution() {
    let suiteName = "MainWindowNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let persistence = UserDefaultsMainWindowAreaPersistence(defaults: defaults)

    let navigation = MainWindowNavigationModel(persistence: persistence)
    let request = RuntimeMutationRequest(operation: .delete(profileID: UUID()))
    navigation.requestArea(.profiles)
    navigation.setProfilesEditorDirty(true)
    #expect(navigation.beginProfilesEditorMutation(request))
    navigation.setProfilesEditorDirty(false)

    navigation.requestArea(.library)

    #expect(navigation.selectedArea == .profiles)
    #expect(navigation.pendingArea == nil)
    #expect(!navigation.isDiscardConfirmationPresented)

    #expect(navigation.finishProfilesEditorMutation(request))
    navigation.setProfilesEditorDirty(true)
    navigation.requestArea(.library)

    #expect(navigation.pendingArea == .library)
    #expect(navigation.isDiscardConfirmationPresented)

    navigation.cancelPendingArea()
    navigation.setProfilesEditorDirty(false)
    navigation.requestArea(.library)
    #expect(navigation.selectedArea == .library)
  }

  @Test
  @MainActor
  func overlappingProfileMutationCannotReleaseFirstNavigationOwner() {
    let suiteName = "MainWindowNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let navigation = MainWindowNavigationModel(
      persistence: UserDefaultsMainWindowAreaPersistence(defaults: defaults)
    )
    let first = RuntimeMutationRequest(operation: .delete(profileID: UUID()))
    let second = RuntimeMutationRequest(operation: .importProfile(profileID: UUID()))

    #expect(navigation.beginProfilesEditorMutation(first))
    #expect(!navigation.beginProfilesEditorMutation(first))
    #expect(!navigation.beginProfilesEditorMutation(second))
    navigation.requestArea(.library)
    #expect(navigation.selectedArea == .controllers)
    #expect(navigation.pendingArea == nil)

    #expect(!navigation.finishProfilesEditorMutation(second))
    navigation.requestArea(.library)
    #expect(navigation.selectedArea == .controllers)
    #expect(navigation.pendingArea == nil)

    #expect(navigation.finishProfilesEditorMutation(first))
    navigation.requestArea(.library)
    #expect(navigation.selectedArea == .library)
  }

  @Test
  @MainActor
  func matchingPreflightFailureReleasesNavigationOwner() {
    let suiteName = "MainWindowNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let navigation = MainWindowNavigationModel(
      persistence: UserDefaultsMainWindowAreaPersistence(defaults: defaults)
    )
    let request = RuntimeMutationRequest(operation: .update(profileID: UUID()))

    #expect(navigation.beginProfilesEditorMutation(request))
    navigation.requestArea(.library)
    #expect(navigation.selectedArea == .controllers)
    #expect(navigation.pendingArea == nil)

    #expect(
      !navigation.finishProfilesEditorMutation(RuntimeMutationRequest(operation: request.operation))
    )
    #expect(navigation.ownsProfilesEditorMutation(request))
    #expect(navigation.finishProfilesEditorMutation(request))

    navigation.setProfilesEditorDirty(false)
    navigation.requestArea(.library)
    #expect(navigation.selectedArea == .library)
  }

  @Test
  @MainActor
  func preflightFailureReleasesBothOwnersAndPreservesDirtyDraft() async {
    let suiteName = "MainWindowNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let original = makeProfile(name: "Original")
    let invalid = makeProfile(id: original.id, name: "")
    let request = RuntimeMutationRequest(operation: .update(profileID: original.id))
    let gateway = GatewayStub(snapshotPayload: snapshot(profiles: [original]))
    let library = ProfileLibraryModel(runtime: RuntimeViewModel(gateway: gateway))
    var transition = ProfileEditorTransitionState()
    let navigation = MainWindowNavigationModel(
      persistence: UserDefaultsMainWindowAreaPersistence(defaults: defaults)
    )

    transition.setDirty(true)
    #expect(transition.beginMutation(request) == .acquired)
    #expect(navigation.beginProfilesEditorMutation(request))

    let result = await library.updateRemappingProfile(
      invalid,
      expectedCurrent: original,
      request: request
    )
    #expect(result.request == request)
    #expect(transition.finishMutationIfOwned(result.request, succeeded: false).didRelease)
    #expect(navigation.finishProfilesEditorMutation(result.request))
    navigation.setProfilesEditorDirty(transition.isDirty)

    navigation.requestArea(.library)
    #expect(navigation.selectedArea == .controllers)
    #expect(navigation.pendingArea == .library)
    #expect(navigation.isDiscardConfirmationPresented)
    #expect(transition.isDirty)
  }
}

/// Records the activation calls of `DockIconController` and delivers resigns on demand.
@MainActor
private final class FakeActivation {
  var isActive = false
  var dockActivation = DockIconController.DockActivation.requested
  private(set) var events: [String] = []
  private var resignHandler: (@MainActor () -> Void)?

  var activation: DockIconController.Activation {
    DockIconController.Activation(
      isActive: { self.isActive },
      activateDock: {
        self.events.append("activate Dock")
        return self.dockActivation
      },
      activateApp: { self.events.append("activate app") },
      observeResignActive: { handler in
        self.events.append("observe")
        self.resignHandler = handler
        return {
          self.events.append("stop")
          self.resignHandler = nil
        }
      }
    )
  }

  func resignActive() {
    isActive = false
    resignHandler?()
  }
}
