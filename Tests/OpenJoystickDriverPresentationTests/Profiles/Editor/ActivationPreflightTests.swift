import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct ActivationPreflightTests {
  private static func profile(_ destination: RemappingDestination) -> RemappingProfile {
    RemappingProfile(
      id: UUID(),
      name: "Actions",
      device: RemappingDeviceScope(vendorID: 0x1234, productID: 0x5678),
      applicationScope: .global,
      bindings: [RemappingBinding(source: .button(.south), destination: destination)]
    )
  }

  @Test
  func launchingActionsAskForConfirmationAndListTheUrlInFull() throws {
    let url = "steam://run/440?launch=1"
    let confirmation = ProfileEditorConfirmation.activation(
      of: Self.profile(.openURL(url)),
      postEventAccess: .granted
    )
    guard case .activateNotice(let message)? = confirmation else {
      Issue.record("No notice for an OpenURL profile")
      return
    }
    #expect(message.contains(url))
  }

  @Test
  func theAlertNamesAMissingPostEventAccess() throws {
    let confirmation = ProfileEditorConfirmation.activation(
      of: Self.profile(.keyboard(key: .a, modifiers: [])),
      postEventAccess: .notAuthorized
    )
    guard case .activateNotice(let message)? = confirmation else {
      Issue.record("No notice for a missing permission")
      return
    }
    #expect(message.contains(RemappingPermission.postEvent.localizedName))
  }

  @Test
  func aProfileWithGrantedAccessAndNoLaunchActivatesWithoutAsking() {
    let confirmation = ProfileEditorConfirmation.activation(
      of: Self.profile(.keyboard(key: .a, modifiers: [])),
      postEventAccess: .granted
    )
    #expect(confirmation == nil)
  }
}
