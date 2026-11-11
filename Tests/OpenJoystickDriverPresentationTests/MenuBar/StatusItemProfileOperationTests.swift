import AppKit
import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct StatusItemProfileOperationTests {
  @MainActor
  private final class BusyWindow: MenuProfileMutating {
    private(set) var requests: [RuntimeMutationRequest] = []
    var hasSelectedProfile: Bool { false }
    var selectedControllerID: String? { nil }
    var enabledToolbarActions: Set<MainWindowToolbarAction> { [] }
    var searchFieldInView: NSSearchField? { nil }
    func perform(_ action: MainWindowToolbarAction) {}
    func focusSearchField() {}

    func showMainWindow(area: MainWindowArea?) {}
    func showAccess(permission: AccessPermissionRow.Kind) {}
    func showErrorCodeExplainer() {}
    func showController(id: String) {}
    func showInputTest(controllerID: String) {}
    func importProfile() {}
    func exportProfile() {}
    func installRecordOrMod() {}

    func performMenuProfileMutation(
      _ request: RuntimeMutationRequest,
      _ mutation: @MainActor (ProfileLibraryModel) async -> RuntimeMutationResult
    ) async -> MenuProfileMutationOutcome? {  // swiftlint:disable:this async_without_await
      requests.append(request)
      return nil
    }
  }

  @Test
  func operationsMapToTheirRuntimeMutation() {
    let id = UUID()
    #expect(
      StatusItemProfileOperation.activate(profileID: id, allowEmpty: false).request.operation
        == .activate(profileID: id)
    )
    #expect(
      StatusItemProfileOperation.deactivate(profileID: id).request.operation
        == .deactivate(profileID: id)
    )
  }

  @Test
  @MainActor
  func operationIsRefusedWithoutSuccessWhileTheEditorHoldsAMutation() async {
    let window = BusyWindow()
    let id = UUID()
    let activated = await StatusItemProfileOperation.activate(profileID: id, allowEmpty: false)
      .perform(on: window)
    let deactivated = await StatusItemProfileOperation.deactivate(profileID: id).perform(on: window)
    #expect(activated == nil)
    #expect(deactivated == nil)
    #expect(window.requests.count == 2)
  }

  private static func emptyProfile() -> RemappingProfile {
    makeProfile().replacing(outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped))
      .removingAllBindings()
  }

  @Test
  func aProfileWithOutputIsActivatedWithoutAsking() {
    let profile = makeProfile()
    let operation = StatusItemProfileOperation.activation(
      of: profile.id,
      in: [profile],
      postEventAccess: .granted
    ) { _ in
      Issue.record("Asked about a profile that produces output")
      return false
    }
    #expect(operation == .activate(profileID: profile.id, allowEmpty: false))
  }

  @Test
  func aProfileWithNoOutputIsActivatedOnlyAfterConfirmation() {
    let profile = Self.emptyProfile()
    #expect(profile.producesNoOutput)
    let confirmed = StatusItemProfileOperation.activation(
      of: profile.id,
      in: [profile],
      postEventAccess: .granted
    ) { _ in
      true
    }
    let declined = StatusItemProfileOperation.activation(
      of: profile.id,
      in: [profile],
      postEventAccess: .granted
    ) { _ in
      false
    }
    #expect(confirmed == .activate(profileID: profile.id, allowEmpty: true))
    #expect(declined == nil)
  }

  @Test
  func aProfileTheLibraryLacksIsActivatedWithoutTheAllowance() {
    let id = UUID()
    #expect(
      StatusItemProfileOperation.activation(of: id, in: [], postEventAccess: nil) { _ in true }
        == .activate(profileID: id, allowEmpty: false)
    )
  }

  @Test
  func aLaunchingProfileIsActivatedOnlyAfterConfirmationWithoutTheEmptyAllowance() {
    let profile = RemappingProfile(
      id: UUID(),
      name: "Actions",
      device: RemappingDeviceScope(vendorID: 0x1234, productID: 0x5678),
      applicationScope: .global,
      bindings: [
        RemappingBinding(source: .button(.south), destination: .openURL("https://example.com/x"))
      ]
    )
    var asked: ProfileEditorConfirmation?
    let confirmed = StatusItemProfileOperation.activation(
      of: profile.id,
      in: [profile],
      postEventAccess: .granted
    ) {
      asked = $0
      return true
    }
    let declined = StatusItemProfileOperation.activation(
      of: profile.id,
      in: [profile],
      postEventAccess: .granted
    ) { _ in false }
    guard case .activateNotice(let message)? = asked else {
      Issue.record("No notice for an OpenURL profile")
      return
    }
    #expect(message.contains("https://example.com/x"))
    #expect(confirmed == .activate(profileID: profile.id, allowEmpty: false))
    #expect(declined == nil)
  }
}
