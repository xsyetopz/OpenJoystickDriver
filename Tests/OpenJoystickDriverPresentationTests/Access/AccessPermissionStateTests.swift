import Foundation
import Testing

@testable import OpenJoystickDriverPresentation

struct AccessPermissionStateTests {
  @Test
  func everyStateHasItsOwnSymbolShape() {
    let names = AccessPermissionState.allCases.map(\.symbolName)
    #expect(Set(names).count == names.count)
    let shapes = names.map { $0.split(separator: ".").prefix(2).joined(separator: ".") }
    #expect(Set(shapes).count == names.count)
  }

  @Test(arguments: AccessPermissionState.allCases)
  func everyStateHasASentenceInEnglish(state: AccessPermissionState) {
    #expect(OJDLocalized.string(state.messageKey) != state.messageKey)
  }

  @Test
  func everyStateHasADistinctSentenceKey() {
    let keys = AccessPermissionState.allCases.map(\.messageKey)
    #expect(Set(keys).count == keys.count)
  }

  @Test
  func readinessStatusesCarryTheirState() {
    let granted = AccessReadiness(
      permissionState: .available(
        RuntimePermissionSummary(inputRead: .granted, inputInject: .denied)
      ),
      statusState: .loading,
      notificationState: .notDetermined,
      notificationSettings: .authorizationOnly(.notDetermined)
    )
    #expect(granted.inputRead.state == .granted)
    #expect(granted.inputInject.state == .denied)
    #expect(granted.notification.state == .notAsked)
    let checking = AccessReadiness(
      permissionState: .loading,
      statusState: .loading,
      notificationState: .checking,
      notificationSettings: .authorizationOnly(.checking)
    )
    #expect(checking.inputRead.state == .checking)
    #expect(checking.postEvent.state == .checking)
  }
}
